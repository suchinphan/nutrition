import sqlite3
import matplotlib.pyplot as plt

# เชื่อมต่อฐานข้อมูล pipeline
conn = sqlite3.connect("pipeline_data.db")
cursor = conn.cursor()

# ดึงจำนวนเมนูแยกตาม region
cursor.execute("""
SELECT region, COUNT(*) 
FROM presentation_zone 
GROUP BY region
""")

data = cursor.fetchall()

regions = [row[0] for row in data]
counts = [row[1] for row in data]

# สร้างกราฟ
plt.figure()
plt.bar(regions, counts)
plt.xticks(rotation=45)
plt.xlabel("Region")
plt.ylabel("Number of Menus")
plt.title("Number of Thai Menus by Region")
plt.tight_layout()
plt.show()

conn.close()