# Design Flow Generator

A powerful, lightweight tool for transforming CSV data into structured design documentation.

## 🚀 Quick Start

1. **Open the app**: Visit [Design Flow Generator](https://ais-commercial-business-unit.github.io/Helix/)
2. **Upload a CSV**: Click the upload area or drag & drop your CSV file
3. **Click "Upload & Generate"**: Sit back while we process your data
4. **Download Design**: Get your markdown file instantly

## 📋 CSV Format

Your CSV should include these columns:

| Column | Description | Examples |
|--------|-------------|----------|
| **domain** | Category/Epic/Business Domain | Billing, Orders, Inventory |
| **event** | Event/Task/Feature Name | Invoice Created, Order Shipped |
| **description** | Details about the event | When invoice is generated... |

### Example CSV
```csv
domain,event,description
Billing,Invoice Created,When a new invoice is generated
Orders,Order Placed,When customer submits order
Inventory,Stock Updated,When inventory levels change
```

## 🎯 What It Does

1. **Parses** your CSV file
2. **Groups** events by domain
3. **Generates** professional markdown documentation
4. **Renders** visual output
5. **Downloads** as `design.md`

## 📊 Features

✅ Drag & drop file upload  
✅ Intelligent column detection  
✅ Automatic domain grouping  
✅ Professional markdown generation  
✅ One-click download  
✅ Real-time preview  
✅ No server required  
✅ Fully client-side  

## 🧪 Test Data

Try uploading `sample-data.csv` to see it in action!

It includes sample events across:
- Billing
- Orders
- Inventory
- Users
- Notifications
- Analytics

## 💡 Use Cases

- **Product Managers**: Create event catalogs for designs
- **Developers**: Generate documentation from domain data
- **Architects**: Build system event specifications
- **Teams**: Collaborate on design flows

## 🛠️ Tech Stack

- **HTML5**: Clean semantic markup
- **CSS3**: Modern, responsive design
- **Vanilla JavaScript**: No dependencies required
- **Marked.js**: Markdown rendering

## 📝 License

Open Source - Use freely!

## 🤝 Contributing

Have improvements? Create a pull request!
