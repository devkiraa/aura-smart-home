#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <Firebase_ESP_Client.h>
#include <Preferences.h>

#include "firebase_config.h"

#define FW_VERSION "3.0-multi-appliance"

// Global Objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
bool firebaseReady = false;
AsyncWebServer server(80);
Preferences preferences;

// Data structure for an appliance
struct Appliance {
  String name;
  uint8_t pin;
  bool state;
};
std::vector<Appliance> appliances;

// --- Function Declarations ---
void loadConfiguration();
void setupFirebase();

void loadConfiguration() {
  preferences.begin("aura-config", true);
  String configJson = preferences.getString("appliances", "[]");
  preferences.end();

  Serial.println("[Config] Loading: " + configJson);
  JsonDocument doc;
  deserializeJson(doc, configJson);
  JsonArray array = doc.as<JsonArray>();

  appliances.clear();
  for (JsonObject obj : array) {
    Appliance appliance;
    appliance.name = obj["name"].as<String>();
    appliance.pin = obj["pin"].as<uint8_t>();
    appliance.state = false; // Always start OFF
    appliances.push_back(appliance);
    pinMode(appliance.pin, OUTPUT);
    digitalWrite(appliance.pin, LOW);
  }
}

void startWebServer() {
  // Endpoint to get the current configuration
  server.on("/config", HTTP_GET, [](AsyncWebServerRequest *request) {
    String configJson = preferences.getString("appliances", "[]");
    request->send(200, "application/json", configJson);
  });

  // Endpoint to save a new configuration
  server.on("/config", HTTP_POST, [](AsyncWebServerRequest *request){}, NULL, [](AsyncWebServerRequest * request, uint8_t *data, size_t len, size_t index, size_t total) {
    String body = "";
    for (size_t i = 0; i < len; i++) { body += (char)data[i]; }
    Serial.println("[Server] New config received: " + body);
    preferences.begin("aura-config", false);
    preferences.putString("appliances", body);
    preferences.end();
    request->send(200, "application/json", "{\"status\":\"ok\"}");
    delay(500);
    ESP.restart();
  });

  // Endpoint to toggle a specific pin
  server.on("/toggle", HTTP_GET, [] (AsyncWebServerRequest *request) {
    if (request->hasParam("pin")) {
      int pin = request->getParam("pin")->value().toInt();
      bool newState = false;
      for (auto& appliance : appliances) {
        if (appliance.pin == pin) {
          appliance.state = !appliance.state;
          digitalWrite(pin, appliance.state);
          newState = appliance.state;
          break;
        }
      }
      request->send(200, "text/plain", newState ? "ON" : "OFF");
      if (firebaseReady) {
        String path = "devices/" + WiFi.macAddress() + "/appliances/" + String(pin) + "/state";
        Firebase.RTDB.setString(&fbdo, path, newState ? "ON" : "OFF");
      }
    } else {
      request->send(400, "text/plain", "Missing pin parameter");
    }
  });

  server.begin();
  Serial.println("[Server] Web server started.");
}

void setupFirebase() {
    Serial.println("[Firebase] Initializing...");
    config.api_key = API_KEY;
    config.database_url = DATABASE_URL;
    config.signer.test_mode = true;
    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);

    if (!Firebase.ready()) {
      Serial.println("[Firebase] Initialization failed.");
      return;
    }
    
    firebaseReady = true;
    Serial.println("[Firebase] Ready.");
    
    String device_path = "devices/" + WiFi.macAddress();
    FirebaseJson json;
    json.set("ip", WiFi.localIP().toString());
    json.set("online", true);
    json.set("version", FW_VERSION);
    // You can add a user-friendly name for the controller from the app later
    json.set("name", "Aura Controller");

    FirebaseJson appliancesJson;
    for(const auto& appliance : appliances) {
      FirebaseJson applianceData;
      applianceData.set("name", appliance.name);
      applianceData.set("type", "Light"); // default type for now
      applianceData.set("state", appliance.state ? "ON" : "OFF");
      appliancesJson.set(String(appliance.pin), applianceData);
    }
    json.set("appliances", appliancesJson);

    if (!Firebase.RTDB.setJSON(&fbdo, device_path.c_str(), &json)) {
      Serial.println("[Firebase] Error updating status: " + fbdo.errorReason());
    }
}

void setupWiFi() {
    preferences.begin("wifi-creds", true);
    String saved_ssid = preferences.getString("ssid", "");
    String saved_pass = preferences.getString("password", "");
    preferences.end();

    if (saved_ssid.length() == 0) {
        Serial.println("[System] No Wi-Fi credentials. Halting until configured via app.");
        return; // Stop here if no Wi-Fi
    }

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
        setupFirebase(); 
        startWebServer(); 
    } else {
        Serial.println("[WiFi] Connection failed!");
    }
}

void setup() {
    Serial.begin(115200);
    Serial.printf("\n[System] Aura Multi-Appliance Controller starting... Version %s\n", FW_VERSION);
    loadConfiguration();
    setupWiFi();
}

void loop() {
  // The loop is free for future features like sensors or timers
}