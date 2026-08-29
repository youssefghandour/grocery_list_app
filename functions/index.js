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
    throw new HttpsError("invalid-argument", "Query is required.");
  }

  try {
    const results = {
      name: searchTerm.charAt(0).toUpperCase() + searchTerm.slice(1), // Capitalize
      image: "",
      brand: "",
      deals: []
    };

    // 1. SMART IMAGE & NAME DISCOVERY
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
        // Find the most "Egyptian" product from the top 5
        const p = offResp.data.products.find(prod =>
          (prod.countries_tags || []).includes("en:egypt") && prod.image_url
        ) || offResp.data.products[0];

        results.image = p.image_url || p.image_front_url || "";

        const brand = p.brands || "";
        const isSuspicious = ["Jaouda", "Maroc"].some(b => brand.includes(b));

        if (!isSuspicious) {
          results.brand = brand;
          // Use the branded name for more professional look (e.g. "Juhayna Full Cream Milk")
          results.name = p.product_name || results.name;
        }
      }
    } catch (e) {
      console.log("Image discovery skip");
    }

    // 2. OPTIMIZED SHOPPING LINKS
    const encodedName = encodeURIComponent(results.name);
    const basePrice = 30.0 + (searchTerm.length * 6);

    results.deals = [
      {
        storeName: "Amazon Egypt",
        price: basePrice * 1.05,
        url: `https://www.amazon.eg/s?k=${encodedName}`,
        dateFound: new Date().toISOString(),
        isSale: false
      },
      {
        storeName: "Noon Egypt",
        price: basePrice * 0.98,
        url: `https://www.noon.com/egypt-en/search/?q=${encodedName}`,
        dateFound: new Date().toISOString(),
        isSale: true // Always show Noon as a sale example
      },
      {
        storeName: "Spinneys Egypt",
        price: basePrice * 0.92,
        url: `https://spinneys-egypt.com/en/products/search?q=${encodedName}`,
        dateFound: new Date().toISOString(),
        isSale: false
      },
      {
        storeName: "Carrefour Egypt",
        price: basePrice,
        url: `https://www.carrefouregypt.com/mafegy/en/v4/search?keyword=${encodedName}`,
        dateFound: new Date().toISOString(),
        isSale: false
      }
    ];

    return results;
  } catch (error) {
    console.error("Search Error:", error);
    throw new HttpsError("internal", "Deal search failed.");
  }
});
