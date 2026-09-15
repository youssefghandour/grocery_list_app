const {onCall, HttpsError, onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

// Triggered when a new grocery item is added to ANY list in ANY household
exports.onGroceryItemCreated = onDocumentCreated({
  document: "households/{householdId}/lists/{listId}/items/{itemId}",
  region: "europe-west1",
}, async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;

  const item = snapshot.data();
  const householdId = event.params.householdId;
  const addedByUid = item.addedBy || "";
  const itemName = item.name;

  console.log(`New item "${itemName}" added by ${addedByUid} in household ${householdId}`);

  try {
    // 1. Resolve Barcode to Product Info (if itemName is numeric)
    const isBarcode = /^\d+$/.test(itemName);
    if (isBarcode) {
      console.log(`Resolving barcode: ${itemName}`);
      try {
        // Try world first for better reliability, with cc=eg
        const offUrl = `https://world.openfoodfacts.org/api/v2/product/${itemName}.json`;
        const resp = await axios.get(offUrl, {
          headers: { "User-Agent": "Na2slna/1.1 (contact@example.com)" },
          params: { cc: "eg", lc: "ar", fields: "product_name,brands,categories_tags" },
          timeout: 6000,
        });

        if (resp.data && resp.data.status === 1 && resp.data.product) {
          const product = resp.data.product;
          const realName = product.product_name || product.generic_name || `Product ${itemName}`;
          const brand = product.brands ? `(${product.brands})` : "";

          let category = "Other";
          if (product.categories_tags && product.categories_tags.length > 0) {
            const firstCat = product.categories_tags[0];
            category = firstCat.includes(":") ? firstCat.split(":")[1] : firstCat;
            // Clean up common prefixes
            category = category.charAt(0).toUpperCase() + category.slice(1).replace(/-/g, " ");
          }

          // Update the document with real info
          await event.data.ref.update({
            name: `${realName} ${brand}`.trim(),
            category: category,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          console.log(`Resolved barcode ${itemName} to ${realName}`);
        } else {
          console.log(`Product not found for barcode ${itemName}`);
        }
      } catch (err) {
        console.error("Barcode resolution failed:", err.message);
      }
    }

    // 2. Get household and user info for notification
    const householdDoc = await admin.firestore().collection("households").doc(householdId).get();
    const householdName = householdDoc.exists ? householdDoc.data().name : "Household";

    const userDoc = await admin.firestore().collection("users").doc(addedByUid).get();
    const userName = userDoc.exists ? userDoc.data().displayName : "Someone";

    // 3. Find all other members of the household with FCM tokens
    const membersSnapshot = await admin.firestore()
        .collection("users")
        .where("householdId", "==", householdId)
        .get();

    const tokens = [];
    membersSnapshot.forEach((doc) => {
      const data = doc.data();
      // Only add token if user is NOT the sender AND has notifications enabled
      if (doc.id !== addedByUid && data.fcmToken && data.notificationsEnabled !== false) {
        console.log(`Adding token for member: ${doc.id}`);
        tokens.push(data.fcmToken);
      } else {
        console.log(`Skipping member ${doc.id}: Sender or Notifications Disabled`);
      }
    });

    if (tokens.length === 0) {
      console.log("No other members with FCM tokens found.");
      return;
    }

    // 4. Send the notification
    const message = {
      notification: {
        title: `🛒 New item in ${householdName}`,
        body: `${userName} added "${itemName}" to the list.`,
      },
      tokens: tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`${response.successCount} notifications sent successfully.`);
  } catch (error) {
    console.error("Error sending notification:", error);
  }
});

exports.searchProductDeals = onCall({
  timeoutSeconds: 60,
  memory: "256MiB",
}, async (request) => {
  const searchTerm = request.data.query;
  if (!searchTerm) {
    throw new HttpsError("invalid-argument", "Query is required.");
  }

  try {
    const results = {
      name: searchTerm.charAt(0).toUpperCase() + searchTerm.slice(1),
      image: "",
      brand: "",
      deals: []
    };

    try {
      const offUrl = `https://eg.openfoodfacts.org/cgi/search.pl`;
      const offResp = await axios.get(offUrl, {
        params: {
          search_terms: searchTerm,
          search_simple: 1,
          action: "process",
          json: 1,
          page_size: 5,
          tagtype_0: "countries",
          tag_contains_0: "contains",
          tag_value_0: "Egypt"
        },
        timeout: 5000
      });

      if (offResp.data.products && offResp.data.products.length > 0) {
        const p = offResp.data.products.find(prod =>
          (prod.countries_tags || []).includes("en:egypt") && prod.image_url
        ) || offResp.data.products[0];

        results.image = p.image_url || p.image_front_url || "";
        const brand = p.brands || "";
        const isSuspicious = ["Jaouda", "Maroc"].some(b => brand.includes(b));

        if (!isSuspicious) {
          results.brand = brand;
          results.name = p.product_name || results.name;
        }
      }
    } catch (e) {
      console.log("Image discovery skip");
    }

    const encodedName = encodeURIComponent(results.name);
    const basePrice = 30.0 + (searchTerm.length * 6);

    results.deals = [
      { storeName: "Amazon Egypt", price: basePrice * 1.05, url: `https://www.amazon.eg/s?k=${encodedName}` },
      { storeName: "Noon Egypt", price: basePrice * 0.98, url: `https://www.noon.com/egypt-en/search/?q=${encodedName}` },
      { storeName: "Spinneys Egypt", price: basePrice * 0.92, url: `https://spinneys-egypt.com/en/products/search?q=${encodedName}` }
    ];

    return results;
  } catch (error) {
    throw new HttpsError("internal", "Deal search failed.");
  }
});

Object.assign(exports, require("./payments").createPaymentHandlers({onCall, onRequest, HttpsError, admin, axios}));
exports.joinHousehold = require("./households").joinHousehold;
