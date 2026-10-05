import numpy as np
import pandas as pd

# 1. Load Dataset
df = pd.read_csv("DataCoSupplyChainDataset.csv", encoding="ISO-8859-1")

# 2. Inspect Missing Values
print("--- Missing Values Count Per Column ---")
print(df.isnull().sum())

# 3. Handle Dates & Standardize Text
df["order date (DateOrders)"] = pd.to_datetime(
    df["order date (DateOrders)"], errors="coerce"
)
df["shipping date (DateOrders)"] = pd.to_datetime(
    df["shipping date (DateOrders)"], errors="coerce"
)

# Strip whitespace and lowercase customer location attributes
for col in ["Customer City", "Customer Country"]:
  df[col] = df[col].astype(str).str.strip().str.lower()

# 4. Filter Invalid Financial & Operational Data
clean_mask = (df["Days for shipping (real)"] >= 0) & (
    df["Order Item Quantity"] > 0
)
df_clean = df[clean_mask].copy()

# 5. Build and Export dim_customer.csv
dim_customer = (
    df_clean[[
        "Customer Id",
        "Customer Fname",
        "Customer Lname",
        "Customer City",
        "Customer Country",
        "Customer Segment",
    ]]
    .drop_duplicates(subset=["Customer Id"])
    .dropna(subset=["Customer Id"])
)

# Convert ID to integer type
dim_customer["Customer Id"] = dim_customer["Customer Id"].astype("int64")

dim_customer.to_csv("dim_customer.csv", index=False)
print(f"dim_customer.csv created successfully with {len(dim_customer)} rows.")

# 6. Build and Export dim_product.csv
# Clean Product Card Id first (handle float conversion & nulls)
df_clean = df_clean.dropna(subset=["Product Card Id"]).copy()
df_clean["Product Card Id"] = df_clean["Product Card Id"].astype("int64")

dim_product = df_clean[[
    "Product Card Id",
    "Product Name",
    "Category Id",
    "Category Name",
    "Product Price",
]].drop_duplicates(subset=["Product Card Id"])

dim_product["Category Id"] = dim_product["Category Id"].astype("int64")

dim_product.to_csv("dim_product.csv", index=False)
print(f"dim_product.csv created successfully with {len(dim_product)} rows.")

# 7. Build and Export fact_orders.csv
fact_orders = df_clean[[
    "Order Item Id",
    "Order Id",
    "Customer Id",
    "Product Card Id",
    "order date (DateOrders)",
    "Days for shipping (real)",
    "Days for shipment (scheduled)",
    "Sales",
    "Order Item Quantity",
    "Benefit per order",
    "Delivery Status",
    "Late_delivery_risk",
]].copy()

# Rename columns to standard SQL-friendly names
fact_orders.columns = [
    "Order_Item_Id",
    "Order_Id",
    "Customer_Id",
    "Product_Card_Id",
    "Order_Date",
    "Days_For_Shipping_Real",
    "Days_For_Shipment_Scheduled",
    "Sales",
    "Order_Item_Quantity",
    "Benefit_Per_Order",
    "Delivery_Status",
    "Late_Risk",
]

# Ensure precise integer casting for foreign keys and counters
fact_orders["Order_Item_Id"] = fact_orders["Order_Item_Id"].astype("int64")
fact_orders["Order_Id"] = fact_orders["Order_Id"].astype("int64")
fact_orders["Customer_Id"] = fact_orders["Customer_Id"].astype("int64")
fact_orders["Product_Card_Id"] = fact_orders["Product_Card_Id"].astype("int64")
fact_orders["Days_For_Shipping_Real"] = fact_orders[
    "Days_For_Shipping_Real"
].astype("int64")
fact_orders["Days_For_Shipment_Scheduled"] = fact_orders[
    "Days_For_Shipment_Scheduled"
].astype("int64")
fact_orders["Order_Item_Quantity"] = fact_orders["Order_Item_Quantity"].astype(
    "int64"
)
fact_orders["Late_Risk"] = fact_orders["Late_Risk"].astype("int64")

fact_orders.to_csv("fact_orders.csv", index=False)
print(f"fact_orders.csv created successfully with {len(fact_orders)} rows.")
