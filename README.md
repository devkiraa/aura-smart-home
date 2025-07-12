# Aura - A DIY Smart Home System

### *Created by ZERODAY*

Aura is a complete, end-to-end DIY smart home platform built from the ground up. It uses affordable ESP32 microcontrollers and a custom Flutter application to provide a powerful, cloud-connected system for controlling any home appliance from anywhere in the world.

## ✨ Key Features

  - **Multi-Appliance Control:** A single ESP32 controller can manage multiple appliances (lights, fans, sockets) connected to a relay module.
  - **Cloud-Based Configuration:** Device and appliance configurations are stored centrally in **Cloud Firestore**, allowing for persistent, user-friendly setup.
  - **Remote & Local Access:** Control appliances from anywhere via the mobile app (using Firebase) or on the local network via a direct web server on the device.
  - **Dynamic Management via App:**
      - Add and manage custom rooms (e.g., Living Room, Bedroom).
      - Configure new controllers and assign them to rooms.
      - Add individual appliances, name them, assign them a GPIO pin, and select a type/icon.
      - Change a device's Wi-Fi credentials after setup.
  - **Real-time Status Sync:** The app's UI updates in real-time to reflect the current state of all appliances.
  - **Over-the-Air (OTA) Updates:** A "Firmware Update" feature in the app pushes new firmware versions from GitHub Releases to all devices automatically.

## ⚙️ System Architecture

```
+----------------+      +-------------------+      +-------------------+
| Aura App       |----->| Firebase Auth     |      |  GitHub Releases  |
+----------------+      +-------------------+      +-------------------+
       |                        ^       ^                      ^
 (Config/Commands)              |       | (Download URL)       | (Firmware.bin)
       |                        |       |                      |
       v                        |       v                      |
+----------------+ <-----> +-------------------+ <------------+
| Cloud Firestore|         | Realtime Database |
| (Appliance     |         | (Live Status &    |
|  Configuration)|         |  Commands)        |
+----------------+ <-----> +-------------------+
                                   ^
                                   | (Bi-directional)
                                   |
                         +-------------------+
                         |  Aura ESP32       |
                         |  Controller       |
                         +-------------------+
                                   |
                         +-------------------+
                         |  Relay Module     |
                         |  (Lights, Fans)   |
                         +-------------------+
```

## 🧰 Hardware Requirements (per controller)

| Component             | Quantity |
| --------------------- | :------: |
| ESP32 Dev Board       |    1     |
| Multi-Channel Relay   |    1     |
| 5V Power Supply       |    1     |
| Jumper Wires & Case   | As needed |

## 🛠️ Technology Stack

  * **Firmware:** C++ on the Arduino Framework with PlatformIO.
  * **Mobile App:** Flutter.
  * **Cloud Backend:** Google Firebase (Authentication, Cloud Firestore, Realtime Database).
  * **Firmware Hosting:** GitHub Releases.

## 🚀 Setup & Installation

### 1\. Firebase Setup

1.  Create a project in the [Firebase Console](https://console.firebase.google.com/).
2.  Enable **Authentication** and add the "Google" sign-in provider.
3.  Enable **Cloud Firestore** and start it in **Test Mode**.
4.  Enable **Realtime Database** and start it in **Test Mode**.
5.  Go to **Project settings \> General** and add an Android app. Follow the steps to download the `google-services.json` file and place it in the `app/android/app/` directory.
6.  Get your **Web API Key**, **Realtime Database URL**, and **Project ID** for the firmware configuration.

### 2\. Firmware Setup

1.  Open the `firmware` directory in VS Code with PlatformIO installed.
2.  Create a file named `firmware/include/firebase_config.h` and add your Firebase credentials:
    ```cpp
    #ifndef FIREBASE_CONFIG_H
    #define FIREBASE_CONFIG_H

    #define API_KEY "YOUR_WEB_API_KEY"
    #define DATABASE_URL "your-rtdb-url.firebaseio.com" // No https://
    #define FIREBASE_PROJECT_ID "YOUR_PROJECT_ID"

    #endif
    ```
3.  Upload the firmware to your ESP32 via USB. For initial setup, the device must be provisioned with your home Wi-Fi credentials (this can be done by flashing an earlier firmware version with BLE provisioning, or by temporarily hardcoding them).

### 3\. App Setup

1.  Open the `app` directory.
2.  Run `flutter pub get` to install all dependencies.
3.  Run the app on your device with `flutter run`.

## 📸 Hardware Setup
<img width="2048" height="2048" alt="Gemini_Generated_Image_1rgppk1rgppk1rgp" src="https://github.com/user-attachments/assets/c931b6f7-1a91-4904-8700-5d20b780c743" />


**ESP32 and Relay Wiring:**


## V2.0 - "Phoenix" Release

This release marks a complete, stable, and feature-rich version of the Aura Smart Home system.

**Release Notes:**

  * **Cloud-Native Configuration:** Devices now fetch their entire appliance configuration from Cloud Firestore, making setup persistent and centralized.
  * **Dynamic Room Management:** The app now supports creating and managing custom rooms, and assigning controllers to them for better organization.
  * **Multi-Appliance UI:** The home screen is organized by rooms, and each controller can be expanded to show and control all of its individual appliances.
  * **Remote & Local Control:** Control is handled via the Realtime Database for remote access and a local web server for direct control.
  * **App-Driven OTA Updates:** A dedicated settings page in the app allows for checking and pushing new firmware versions hosted on GitHub Releases.
