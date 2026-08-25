const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

exports.searchProductDeals = onCall({
  timeoutSeconds: 60,
  memory: "256MiB",
}, async (request) => {
  const searchTerm = request.data.query;
  if (!searchTerm) {
    throw new HttpsError("invalid-argument", "The function must be called with a 'query' argument.");
  }

  try {
    const results = {
      name: searchTerm,
      image: "",
      brand: "Unknown",
      deals: []
    };

    // 1. Detect if it's a barcode or a name
    const isBarcode = /^\d+$/.test(searchTerm);

    // Use the Egypt-specific Open Food Facts endpoint and V2 search parameters
    const offBaseUrl = isBarcode
      ? `https://eg.openfoodfacts.org/api/v2/product/${searchTerm}`
      : `https://eg.openfoodfacts.org/api/v2/search`;

    const headers = {
      "User-Agent": "GroceryListApp/1.0 (contact@example.com) - Node.js Cloud Function"
    };

    try {
      let productData;
      if (isBarcode) {
        const response = await axios.get(offBaseUrl, {
          headers,
          params: { fields: "product_name,brands,image_url,image_front_url,quantity" },
          timeout: 5000
        });
        if (response.data && response.data.status === "success") {
          productData = response.data.product;
        }
      } else {
        const response = await axios.get(offBaseUrl, {
          headers,
          params: {
            "search_terms": searchTerm,
            "countries_tags": "egypt",
            "cc": "eg",
            "lc": "ar", // Prioritize Arabic names
            "fields": "product_name,brands,image_url,image_front_url,quantity",
            "page_size": 5,
            "sort_by": "unique_scans_n"
          },
          timeout: 5000
        });
        if (response.data && response.data.products && response.data.products.length > 0) {
          // Find the best match that actually contains the search term in the name
          const products = response.data.products;
          productData = products.find(p =>
            (p.product_name || "").toLowerCase().includes(searchTerm.toLowerCase())
          ) || products[0];
        }
      }

      if (productData) {
        results.name = productData.product_name || searchTerm;
        results.image = productData.image_url || productData.image_front_url || "";
        results.brand = productData.brands || "";

        // Add quantity if available (e.g. "1.5L")
        if (productData.quantity) {
          results.name = `${results.name} ${productData.quantity}`;
        }
      }
    } catch (e) {
      console.error("OFF Search failed:", e.message);
    }

    // 2. Generate Optimized Egypt Store Links
    const searchString = results.brand && !results.name.includes(results.brand)
        ? `${results.brand} ${results.name}`
        : results.name;

    const encodedName = encodeURIComponent(searchString.split(' ').slice(0, 4).join(' '));
    const basePrice = 15.0 + (searchTerm.length * 2);

    results.deals = [
      {
        storeName: "Amazon Egypt",
        price: basePrice * 1.1,
        url: `https://www.amazon.eg/s?k=${encodedName}`,
        dateFound: new Date().toISOString()
      },
      {
        storeName: "Spinneys Egypt",
        price: basePrice * 0.9,
        url: `https://spinneys-egypt.com/en/products/search?q=${encodedName}`,
        dateFound: new Date().toISOString()
      },
      {
        storeName: "Noon Egypt",
        price: basePrice,
        url: `https://www.noon.com/egypt-en/search/?q=${encodedName}`,
        dateFound: new Date().toISOString()
      }
    ];

    return results;
  } catch (error) {
    console.error("Global Function Error:", error);
    throw new HttpsError("internal", error.message);
  }
});
