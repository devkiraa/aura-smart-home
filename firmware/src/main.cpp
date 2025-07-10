#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <Update.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <ESPAsyncWebServer.h>
#include <Firebase_ESP_Client.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include "firebase_config.h"

// --- FIRMWARE VERSION ---
#define FW_VERSION "1.0"

// --- Pin Definition ---
const int RELAY_PIN = 2; // Built-in LED

// --- Firebase Objects ---
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
bool firebaseReady = false;

// --- Web Server ---
AsyncWebServer server(80);

// --- BLE Definitions ---
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CONFIG_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

Preferences preferences;

// --- Function Declarations ---
void setupFirebase();
void startWebServer();
void setupOTA();
void performOTA(String url);
void checkForOTAUpdates();

// --- OTA CHECK & UPDATE LOGIC ---
unsigned long previousOTACheck = 0;
const long otaCheckInterval = 300000; // Check for updates every 5 minutes (300,000 ms)

void performOTA(String url) {
    Serial.println("[OTA] Starting HTTP OTA Update...");
    HTTPClient http;
    http.begin(url);
    int httpCode = http.GET();
    if (httpCode == HTTP_CODE_OK) {
        int len = http.getSize();
        if (!Update.begin(len)) {
            Serial.println("[OTA] ERROR: Not enough space to begin OTA");
            return;
        }
        WiFiClient& stream = http.getStream();
        while (http.connected() && Update.isRunning()) {
            size_t bytesRead = stream.available();
            if (bytesRead) {
                Update.writeStream(stream);
                Serial.printf("[OTA] Progress: %d%%\r", (Update.progress() * 100) / Update.size());
            }
        }
        if (Update.end()) {
            Serial.println("\n[OTA] Update successful! Restarting...");
            ESP.restart();
        } else {
            Serial.println("[OTA] Error Occurred: " + String(Update.getError()));
        }
    } else {
        Serial.println("[OTA] ERROR: Could not download binary. HTTP Code: " + String(httpCode));
    }
    http.end();
}

void checkForOTAUpdates() {
    if (!firebaseReady) return;

    String path = "/firmware/latest_version";
    if (Firebase.RTDB.getString(&fbdo, path.c_str())) {
        String latest_version = fbdo.stringData();
        if (latest_version != FW_VERSION) {
            Serial.printf("[OTA] New firmware found. Current: %s, Latest: %s\n", FW_VERSION, latest_version.c_str());
            String url_path = "/firmware/download_url";
            if (Firebase.RTDB.getString(&fbdo, url_path.c_str())) {
                performOTA(fbdo.stringData());
            }
        } else {
             Serial.println("[OTA] Firmware is up to date.");
        }
    }
}

// --- BLE Callbacks ---
class MyCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        if (value.length() > 0) {
            Serial.println("\n[BLE] Received new configuration.");
            JsonDocument doc;
            deserializeJson(doc, value);
            const char* ssid = doc["ssid"];
            const char* password = doc["pass"];
            
            preferences.begin("wifi-creds", false);
            preferences.putString("ssid", ssid);
            preferences.putString("password", password);
            preferences.end();
            
            Serial.println("[BLE] Credentials saved! Restarting...");
            delay(1000);
            ESP.restart();
        }
    }
};

void startBleProvisioning() {
    Serial.println("[BLE] Starting Provisioning Mode...");
    BLEDevice::init("Aura-Setup");
    BLEDevice::setMTU(512);
    BLEServer *pServer = BLEDevice::createServer();
    BLEService *pService = pServer->createService(SERVICE_UUID);
    BLECharacteristic *pConfigCharacteristic = pService->createCharacteristic(
        CONFIG_CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_WRITE);
    pConfigCharacteristic->setCallbacks(new MyCallbacks());
    pService->start();
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Waiting for mobile app...");
}

// --- Local OTA Setup Function ---
void setupOTA() {
  Serial.println("[OTA] Initializing Local OTA...");
  ArduinoOTA.setHostname("aura-device");
  ArduinoOTA.setPassword("aura_ota_password");

  ArduinoOTA
    .onStart([]() {
      String type;
      if (ArduinoOTA.getCommand() == U_FLASH)
        type = "sketch";
      else // U_SPIFFS
        type = "filesystem";
      Serial.println("[OTA] Start updating " + type);
    })
    .onEnd([]() {
      Serial.println("\n[OTA] End");
    })
    .onProgress([](unsigned int progress, unsigned int total) {
      Serial.printf("[OTA] Progress: %u%%\r", (progress / (total / 100)));
    })
    .onError([](ota_error_t error) {
      Serial.printf("[OTA] Error[%u]: ", error);
      if (error == OTA_AUTH_ERROR) Serial.println("Auth Failed");
      else if (error == OTA_BEGIN_ERROR) Serial.println("Begin Failed");
      else if (error == OTA_CONNECT_ERROR) Serial.println("Connect Failed");
      else if (error == OTA_RECEIVE_ERROR) Serial.println("Receive Failed");
      else if (error == OTA_END_ERROR) Serial.println("End Failed");
    });

  ArduinoOTA.begin();
  Serial.println("[OTA] Local OTA Service ready.");
}


// --- Wi-Fi, Firebase, and Web Server Setup ---
void setupWiFi() {
    preferences.begin("wifi-creds", true);
    String saved_ssid = preferences.getString("ssid", "");
    String saved_pass = preferences.getString("password", "");
    preferences.end();

    WiFi.begin(saved_ssid.c_str(), saved_pass.c_str());
    Serial.print("[WiFi] Connecting");
    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < 20) {
        delay(500);
        Serial.print(".");
        retries++;
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("[WiFi] Connected!");
        Serial.print("  IP Address: ");
        Serial.println(WiFi.localIP());

        if (MDNS.begin("aura-device")) {
            Serial.println("[mDNS] Responder started");
        }
        
        setupFirebase(); 
        startWebServer(); 
        setupOTA();
    } else {
        Serial.println("[WiFi] Connection failed! Clearing credentials...");
        preferences.begin("wifi-creds", false);
        preferences.clear();
        preferences.end();
        delay(1000);
        ESP.restart();
    }
}

void setupFirebase() {
    Serial.println("[Firebase] Initializing...");
    config.api_key = API_KEY;
    config.database_url = DATABASE_URL;

    config.signer.test_mode = true;
    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);

    unsigned long startMillis = millis();
    while (!Firebase.ready() && millis() - startMillis < 5000) {
        Serial.print(".");
        delay(500);
    }

    if (Firebase.ready()) {
        firebaseReady = true;
        Serial.println("[Firebase] Ready.");
        
        String device_path = "devices/" + WiFi.macAddress();
        FirebaseJson json;
        json.set("ip", WiFi.localIP().toString());
        json.set("online", true);
        json.set("state", digitalRead(RELAY_PIN) == HIGH ? "ON" : "OFF");
        json.set("version", FW_VERSION);
        if (Firebase.RTDB.setJSON(&fbdo, device_path.c_str(), &json)) {
            Serial.println("[Firebase] Device status updated.");
        } else {
            Serial.println("[Firebase] Error updating status: " + fbdo.errorReason());
        }
    } else {
        Serial.println("[Firebase] Initialization failed.");
    }
}

void startWebServer() {
    server.on("/on", HTTP_GET, [](AsyncWebServerRequest *request){
        digitalWrite(RELAY_PIN, HIGH);
        request->send(200, "text/plain", "Device turned ON");
        if (firebaseReady) Firebase.RTDB.setString(&fbdo, "devices/" + WiFi.macAddress() + "/state", "ON");
    });

    server.on("/off", HTTP_GET, [](AsyncWebServerRequest *request){
        digitalWrite(RELAY_PIN, LOW);
        request->send(200, "text/plain", "Device turned OFF");
        if (firebaseReady) Firebase.RTDB.setString(&fbdo, "devices/" + WiFi.macAddress() + "/state", "OFF");
    });

    server.begin();
    Serial.println("[Server] Web server started.");
}

// --- Main Setup and Loop ---
void setup() {
    Serial.begin(115200);
    pinMode(RELAY_PIN, OUTPUT);
    digitalWrite(RELAY_PIN, LOW); 

    Serial.printf("\n[System] Aura device starting... Version %s\n", FW_VERSION);
    preferences.begin("wifi-creds", true);
    String saved_ssid = preferences.getString("ssid", "");
    preferences.end();

    if (saved_ssid == "") {
        startBleProvisioning();
    } else {
        setupWiFi();
    }
}

void loop() {
  ArduinoOTA.handle(); // Handles local OTA from PlatformIO IDE
  
  // Check for HTTP OTA updates periodically
  unsigned long currentMillis = millis();
  if (currentMillis - previousOTACheck >= otaCheckInterval) {
    previousOTACheck = currentMillis;
    checkForOTAUpdates();
  }
}