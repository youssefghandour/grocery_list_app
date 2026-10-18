const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

const syncToken = defineSecret("CARREFOUR_CATALOG_SYNC_TOKEN");
const DEFAULT_STORE = "carrefour";
const MAX_BATCH_SIZE = 200;
const MAX_SEARCH_RESULTS = 5000;

const db = () => admin.firestore();

const normalizeText = value => String(value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();

const tokensFor = value => [...new Set(normalizeText(value)
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean))];

const parseNumber = value => {
  if (value === null || value === undefined || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : null;
};

const error = (res, status, message) => res.status(status).json({error: message});

const productFromDoc = doc => ({id: doc.id, ...doc.data()});

const findProducts = async (query, filters = {}) => {
  const words = query.trim().split(/\s+/).filter(Boolean).map(normalizeText);
  let ref = db().collection("carrefourProducts");
  if (words.length > 0) {
    // searchTokens is populated by the trusted sync endpoint. Any-token matches
    // are narrowed to all query words below, avoiding unsupported full-text queries.
    ref = ref.where("searchTokens", "array-contains-any", words.slice(0, 30));
  }
  const snapshot = await ref.limit(MAX_SEARCH_RESULTS).get();
  return snapshot.docs.map(productFromDoc).filter(product => {
    const haystack = normalizeText(`${product.name || ""} ${product.brand || ""}`);
    if (!words.every(word => haystack.includes(word))) return false;
    if (filters.store && product.store !== filters.store) return false;
    if (filters.brand && !normalizeText(product.brand).includes(normalizeText(filters.brand))) return false;
    if (filters.minPrice !== null && (product.price === null || product.price < filters.minPrice)) return false;
    if (filters.maxPrice !== null && (product.price === null || product.price > filters.maxPrice)) return false;
    if (filters.onSale && !(product.old_price !== null && product.old_price > product.price)) return false;
    return true;
  });
};

exports.carrefourApi = onRequest({
  region: "europe-west1",
  invoker: "public",
  timeoutSeconds: 60,
  memory: "512MiB",
  cors: true,
}, async (req, res) => {
  if (req.method !== "GET") return error(res, 405, "Method not allowed");
  const authorization = req.get("authorization") || "";
  const tokenMatch = authorization.match(/^Bearer\s+(.+)$/i);
  if (!tokenMatch) return error(res, 401, "Sign in is required");
  try {
    await admin.auth().verifyIdToken(tokenMatch[1]);
  } catch (_err) {
    return error(res, 401, "Sign in is required");
  }
  const path = req.path.replace(/\/$/, "") || "/";

  try {
    if (path === "/health") {
      const snapshot = await db().collection("carrefourProducts").count().get();
      const latest = await db().collection("carrefourProducts")
          .orderBy("last_seen", "desc").limit(1).get();
      return res.json({
        ok: true,
        products: snapshot.data().count,
        last_update: latest.empty ? null : latest.docs[0].data().last_seen || null,
      });
    }

    if (path === "/products") {
      const sort = req.query.sort || "name";
      if (!["name", "price_asc", "price_desc", "recent"].includes(sort)) {
        return error(res, 400, "Invalid sort value");
      }
      const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 50, 1), 500);
      const offset = Math.max(Number.parseInt(req.query.offset, 10) || 0, 0);
      const minPrice = req.query.min_price === undefined ? null : parseNumber(req.query.min_price);
      const maxPrice = req.query.max_price === undefined ? null : parseNumber(req.query.max_price);
      if (req.query.min_price !== undefined && minPrice === null ||
          req.query.max_price !== undefined && maxPrice === null) {
        return error(res, 400, "Invalid price filter");
      }
      const all = await findProducts(String(req.query.q || ""), {
        store: String(req.query.store || DEFAULT_STORE),
        brand: req.query.brand ? String(req.query.brand) : "",
        minPrice,
        maxPrice,
        onSale: req.query.on_sale === "true",
      });
      const sorters = {
        name: (a, b) => String(a.name || "").localeCompare(String(b.name || "")),
        price_asc: (a, b) => (a.price === null ? 1 : b.price === null ? -1 : a.price - b.price),
        price_desc: (a, b) => (b.price || 0) - (a.price || 0),
        recent: (a, b) => String(b.last_seen || "").localeCompare(String(a.last_seen || "")),
      };
      all.sort(sorters[sort]);
      const items = all.slice(offset, offset + limit).map(product => ({
        id: product.id,
        store: product.store || DEFAULT_STORE,
        name: product.name,
        brand: product.brand || null,
        price: product.price === undefined ? null : product.price,
        old_price: product.old_price === undefined ? null : product.old_price,
        url: product.url || null,
        last_seen: product.last_seen || null,
      }));
      return res.json({total: all.length, limit, offset, items});
    }

    const historyMatch = path.match(/^\/products\/([^/]+)\/history$/);
    if (historyMatch) {
      const productId = decodeURIComponent(historyMatch[1]);
      const productRef = db().collection("carrefourProducts").doc(productId);
      const product = await productRef.get();
      if (!product.exists) return error(res, 404, "Product not found");
      const history = await productRef.collection("priceHistory").orderBy("seen_at").get();
      return res.json({product_id: productId, history: history.docs.map(doc => doc.data())});
    }

    const productMatch = path.match(/^\/products\/([^/]+)$/);
    if (productMatch) {
      const productId = decodeURIComponent(productMatch[1]);
      const product = await db().collection("carrefourProducts").doc(productId).get();
      if (!product.exists) return error(res, 404, "Product not found");
      const value = productFromDoc(product);
      delete value.searchTokens;
      return res.json(value);
    }

    return error(res, 404, "Not found");
  } catch (err) {
    console.error("Carrefour API request failed", err.code || err.message);
    return error(res, 500, "Carrefour API request failed");
  }
});

exports.syncCarrefourCatalog = onRequest({
  region: "europe-west1",
  timeoutSeconds: 120,
  memory: "512MiB",
  secrets: [syncToken],
}, async (req, res) => {
  if (req.method !== "POST") return error(res, 405, "Method not allowed");
  const suppliedToken = String(req.get("x-catalog-sync-token") || "").trim();
  const expectedToken = String(syncToken.value() || "").trim();
  if (!suppliedToken || !expectedToken || suppliedToken !== expectedToken) {
    console.warn("Catalog sync rejected an invalid token", {
      supplied: Boolean(suppliedToken),
      configured: Boolean(expectedToken),
    });
    return error(res, 401, "Unauthorized");
  }

  const items = req.body && req.body.items;
  if (!Array.isArray(items) || items.length === 0 || items.length > MAX_BATCH_SIZE) {
    return error(res, 400, `items must contain 1 to ${MAX_BATCH_SIZE} products`);
  }

  const validItems = [];
  for (const item of items) {
    if (!item || typeof item !== "object" || typeof item.id !== "string" ||
        !item.id || item.id.includes("/") || typeof item.name !== "string" ||
        !item.name.trim() || item.name.length > 512) {
      return error(res, 400, "Each product needs a valid id and name");
    }
    const price = parseNumber(item.price);
    const oldPrice = parseNumber(item.old_price);
    if (item.price !== null && item.price !== undefined && price === null ||
        item.old_price !== null && item.old_price !== undefined && oldPrice === null) {
      return error(res, 400, "Product price must be a non-negative number or null");
    }
    const name = item.name.trim();
    const brand = typeof item.brand === "string" ? item.brand.trim().slice(0, 120) : "";
    const url = typeof item.url === "string" ? item.url.slice(0, 4096) : "";
    const lastSeen = typeof item.last_seen === "string" ? item.last_seen : new Date().toISOString();
    validItems.push({
      id: item.id,
      data: {
        store: typeof item.store === "string" && item.store.trim() ? item.store.trim() : DEFAULT_STORE,
        name,
        brand,
        price,
        old_price: oldPrice,
        url,
        first_seen: typeof item.first_seen === "string" ? item.first_seen : lastSeen,
        last_seen: lastSeen,
        searchTokens: tokensFor(`${name} ${brand}`),
      },
    });
  }

  try {
    const firestore = db();
    const refs = validItems.map(item => firestore.collection("carrefourProducts").doc(item.id));
    const existing = await firestore.getAll(...refs);
    const batch = firestore.batch();
    const stamp = admin.firestore.FieldValue.serverTimestamp();
    let historyCount = 0;
    validItems.forEach((item, index) => {
      const ref = refs[index];
      const previous = existing[index].exists ? existing[index].data() : null;
      batch.set(ref, {
        ...item.data,
        first_seen: previous && previous.first_seen || item.data.first_seen,
        synced_at: stamp,
      }, {merge: true});
      if (!previous || previous.price !== item.data.price) {
        const historyRef = ref.collection("priceHistory").doc();
        batch.set(historyRef, {price: item.data.price, seen_at: item.data.last_seen});
        historyCount++;
      }
    });
    await batch.commit();
    return res.json({ok: true, received: validItems.length, history_entries: historyCount});
  } catch (err) {
    console.error("Carrefour catalog sync failed", err.code || err.message);
    return error(res, 500, "Catalog sync failed");
  }
});
