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

_Add your app screenshots here_

---

## ⚙️ Setup Instructions

### 1. Clone Repo
```bash
git clone https://github.com/your-username/lifelink.git
cd lifelink
