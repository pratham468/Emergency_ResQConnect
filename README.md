Emergency_ResQConnect
is a real-time emergency assistance application that connects users with **nearest blood banks** and **ambulance services** instantly.

---

## 🚀 Features

### 👤 User (Patient)
- 🚑 Request Ambulance
- 🩸 Request Blood (by group & units)
- 📍 Find nearest blood banks
- 🗺️ Live tracking (ambulance / blood bank route)
- 📜 View history (ambulance + blood requests)

---

### 🚑 Ambulance Driver
- 📡 Receive emergency requests
- ✅ Accept / Reject requests
- 📍 Live location tracking
- 🚗 Navigate to user

---

### 🏥 Blood Bank Manager
- 🧾 Register blood bank with location
- 📦 Manage blood stock (group-wise)
- 👀 View inventory
- 🔄 Update real-time stock

---

## 🛠️ Tech Stack

- **Frontend:** Flutter  
- **Backend:** Firebase  
- **Database:** Cloud Firestore  
- **Authentication:** Firebase Auth  
- **Maps & Location:** Flutter Map / OpenStreetMap  
- **Real-time Tracking:** Firestore Streams  

---

## 🔥 How It Works

### 🚑 Ambulance Flow
1. User sends emergency request  
2. Nearest available ambulance is assigned  
3. Driver accepts request  
4. Live tracking starts  
5. Request completes  

---

### 🩸 Blood Request Flow
1. User selects blood group & units  
2. System checks nearest blood banks  
3. Filters based on availability  
4. Shows list sorted by distance  
5. User selects → tracking screen  

---

## 📸 Screenshots

<img width="1080" height="2412" alt="WhatsApp Image 2026-06-07 at 11 07 46 AM" src="https://github.com/user-attachments/assets/2108bb9c-f00b-4115-a704-2694889cf258" />

<img width="716" height="1600" alt="WhatsApp Image 2026-06-07 at 11 07 45 AM" src="https://github.com/user-attachments/assets/b6744937-b8e5-4e10-96fa-dab7d5fef99a" />

<img width="716" height="1600" alt="WhatsApp Image 2026-06-07 at 11 07 44 AM" src="https://github.com/user-attachments/assets/45465c60-8dc0-4821-9f3b-a9e2806c4933" />

---

## ⚙️ Setup Instructions

### 1. Clone Repo
bash
https://github.com/pratham468/Emergency_ResQConnect.git
cd emergency_blood_bank

### 2. install dependencies
flutter pub get

### 3.firebase setup

Create Firebase project
Enable Authentication
Create Firestore database
Add google-services.json / firebase_options.dart

### 4.Run App
flutter run
