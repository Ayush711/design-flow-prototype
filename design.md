# Design Flow Document

> This system contains 6 domains and 20 events.

---

## Domain: Analytics

* **Event: Report Generated**
  Description: When a scheduled or on-demand report is created

* **Event: Dashboard Updated**
  Description: When real-time dashboard metrics are refreshed

---

## Domain: Billing

* **Event: Invoice Created**
  Description: When a new invoice is generated for a customer order

* **Event: Payment Received**
  Description: When payment is successfully processed and recorded

* **Event: Refund Issued**
  Description: When a refund is processed for returned items or cancellations

* **Event: Subscription Renewed**
  Description: When a recurring subscription payment is processed

---

## Domain: Inventory

* **Event: Stock Updated**
  Description: When inventory levels are adjusted after shipment or receipt

* **Event: Low Stock Alert**
  Description: When product inventory falls below minimum threshold

* **Event: Reorder Triggered**
  Description: When automatic reorder is initiated for low stock items

---

## Domain: Notifications

* **Event: Email Sent**
  Description: When system sends an email notification to user

* **Event: SMS Sent**
  Description: When system sends an SMS alert to user

* **Event: Push Notification**
  Description: When mobile push notification is triggered

---

## Domain: Orders

* **Event: Order Placed**
  Description: When a customer submits a new order through the system

* **Event: Order Shipped**
  Description: When an order is dispatched from the warehouse

* **Event: Order Delivered**
  Description: When delivery is confirmed at customer location

* **Event: Order Cancelled**
  Description: When a customer or system cancels an active order

---

## Domain: Users

* **Event: User Registered**
  Description: When a new user account is created in the system

* **Event: User Logged In**
  Description: When a user successfully authenticates

* **Event: Password Reset**
  Description: When a user requests or completes password reset

* **Event: Profile Updated**
  Description: When user updates their account information

---


*Generated on 15/04/2026 at 12:11:14*
