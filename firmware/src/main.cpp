#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <Firebase_ESP_Client.h>
#include <Preferences.h>
#include "firebase_config.h"

#define FW_VERSION "5.2-sync-fix"
#define ONBOARD_LED 2

// --- Global Objects & Data Structures ---
FirebaseData fbdo;
FirebaseData command_stream;
FirebaseData appliance_stream;
FirebaseAuth auth;
FirebaseConfig config;
bool firebaseReady = false;
AsyncWebServer server(80);
Preferences preferences;
struct Appliance { String name; uint8_t pin; bool state; };
std::vector<Appliance> appliances;

// --- Function Declarations ---
void applianceStreamCallback(FirebaseStream data);
void commandStreamCallback(FirebaseStream data);
void streamTimeoutCallback(bool timeout);
void loadConfigurationFromFirestore();
void setupFirebase();
void startWebServer();
void setupWiFi();

// --- Core Functions ---
void loadConfigurationFromFirestore() {
  if (!firebaseReady) return;
  String documentPath = "device_configs/" + WiFi.macAddress();
  Serial.println("[Firestore] Fetching config from: " + documentPath);
  if (Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "", documentPath.c_str(), "")) {
    JsonDocument doc;
    deserializeJson(doc, fbdo.payload().c_str());
    if (doc.containsKey("fields") && doc["fields"].containsKey("appliances")) {
      JsonArray array = doc["fields"]["appliances"]["arrayValue"]["values"];
      appliances.clear();
      Serial.println("  [+] Found " + String(array.size()) + " appliances.");
      for (JsonObject obj : array) {
        Appliance appliance;
        appliance.name = obj["mapValue"]["fields"]["name"]["stringValue"].as<String>();
        appliance.pin = obj["mapValue"]["fields"]["pin"]["integerValue"].as<int>();
        appliance.state = false;
        appliances.push_back(appliance);
        pinMode(appliance.pin, OUTPUT);
        digitalWrite(appliance.pin, LOW);
      }
    }
  } else {
    Serial.println("  [-] Firestore Get Failed: " + fbdo.errorReason());
  }
}

void applianceStreamCallback(FirebaseStream data) {
  String pinStr = data.dataPath().substring(1, data.dataPath().lastIndexOf('/'));
  int pin = pinStr.toInt();
  bool newState = (data.stringData() == "ON");
  for (auto& appliance : appliances) {
    if (appliance.pin == pin) {
      appliance.state = newState;
      digitalWrite(pin, newState);
      Serial.printf("  [->] Remote Toggled GPIO %d to %s\n", pin, newState ? "ON" : "OFF");
      break;
    }
  }
}

void commandStreamCallback(FirebaseStream data) {
  if (data.dataTypeEnum() == fb_esp_rtdb_data_type_string && data.stringData() == "REBOOT") {
    Serial.println("\n<REBOOT> Command received! Restarting...");
    Firebase.RTDB.deleteNode(&fbdo, data.streamPath());
    delay(1000);
    ESP.restart();
  }
}

void streamTimeoutCallback(bool timeout) {
  if (timeout) Serial.println("[!] RTDB Stream timeout.");
}

// --- UPDATED FIREBASE SETUP ---
void setupFirebase() {
    Serial.println("\n--- [ FIREBASE INIT ] ---");
    config.api_key = API_KEY;
    config.database_url = DATABASE_URL;
    config.signer.test_mode = true;
    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);

    if (!Firebase.ready()) { Serial.println("  [-] Authentication Failed."); return; }
    
    firebaseReady = true;
    Serial.println("  [+] Authentication Success.");
    
    loadConfigurationFromFirestore();
    
    String commandPath = "devices/" + WiFi.macAddress() + "/command";
    Firebase.RTDB.beginStream(&command_stream, commandPath.c_str());
    Firebase.RTDB.setStreamCallback(&command_stream, commandStreamCallback, streamTimeoutCallback);
    
    String appliancesPath = "devices/" + WiFi.macAddress() + "/appliances";
    Firebase.RTDB.beginStream(&appliance_stream, appliancesPath.c_str());
    Firebase.RTDB.setStreamCallback(&appliance_stream, applianceStreamCallback, streamTimeoutCallback);
    Serial.println("  [+] RTDB Stream listeners active.");

    // --- THIS IS THE FIX ---
    // Report the full device status, INCLUDING the initial state of all appliances
    String device_path = "devices/" + WiFi.macAddress();
    FirebaseJson status_json;
    status_json.set("ip", WiFi.localIP().toString());
    status_json.set("online", true);
    status_json.set("version", FW_VERSION);
    status_json.set("name", "ZERODAY Controller");

    FirebaseJson appliances_json;
    for(const auto& appliance : appliances) {
      FirebaseJson appliance_data;
      appliance_data.set("name", appliance.name);
      appliance_data.set("state", appliance.state ? "ON" : "OFF");
      appliances_json.set(String(appliance.pin), appliance_data);
    }
    status_json.set("appliances", appliances_json);
    
    // Use setJSON to overwrite the whole device node with the new, complete data
    if (Firebase.RTDB.setJSON(&fbdo, device_path.c_str(), &status_json)) {
      Serial.println("  [+] Full device status reported to RTDB.");
    } else {
      Serial.println("  [-] RTDB Set Failed: " + fbdo.errorReason());
    }
}

void startWebServer() {
  Serial.println("\n--- [ LOCAL API INIT ] ---");
  server.on("/toggle", HTTP_GET, [] (AsyncWebServerRequest *request) {
    if (request->hasParam("pin")) {
      int pin = request->getParam("pin")->value().toInt();
      bool newState = false;
      for (auto& appliance : appliances) {
        if (appliance.pin == pin) {
          appliance.state = !appliance.state;
          digitalWrite(appliance.pin, appliance.state); // Corrected logic
          newState = appliance.state;
          break;
        }
      }
      request->send(200, "text/plain", newState ? "ON" : "OFF");
      if (firebaseReady) {
        String path = "devices/" + WiFi.macAddress() + "/appliances/" + String(pin) + "/state";
        Firebase.RTDB.setString(&fbdo, path.c_str(), newState ? "ON" : "OFF");
      }
    }
  });
  // ... reconfigure-wifi endpoint is unchanged ...
  server.begin();
  Serial.println("  [+] Web server running.");
}

void setupWiFi() {
    Serial.println("\n--- [ WIFI SETUP ] ---");
    preferences.begin("wifi-creds", true);
    String saved_ssid = preferences.getString("ssid", "");
    String saved_pass = preferences.getString("password", "");
    preferences.end();
    
    if (saved_ssid.length() == 0) {
      Serial.println("  [!] No credentials found. Halting.");
      return;
    }

    WiFi.begin(saved_ssid.c_str(), saved_pass.c_str());
    Serial.print("  [..] Attempting connection to " + saved_ssid);
    
    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < 40) {
        digitalWrite(ONBOARD_LED, HIGH); delay(75);
        digitalWrite(ONBOARD_LED, LOW); delay(75);
        Serial.print(".");
        retries++;
    }
    Serial.println();
    
    if (WiFi.status() == WL_CONNECTED) {
        digitalWrite(ONBOARD_LED, LOW);
        Serial.println("  [+] Connection Established!");
        Serial.print("      IP Address: "); Serial.println(WiFi.localIP());
        setupFirebase(); 
        startWebServer(); 
    } else {
        Serial.println("  [-] Connection Failed!");
        for (int i=0; i<3; i++) {
          digitalWrite(ONBOARD_LED, HIGH); delay(500);
          digitalWrite(ONBOARD_LED, LOW); delay(500);
        }
    }
}

void setup() {
    Serial.begin(115200);
    pinMode(ONBOARD_LED, OUTPUT);
    digitalWrite(ONBOARD_LED, LOW); 

    Serial.println("\n\n");
    Serial.println("      ███████╗███████╗██████╗  ██████╗  ██████╗  █████╗ ██╗   ██╗");
    Serial.println("      ██╔════╝██╔════╝██╔══██╗██╔═══██╗██╔════╝ ██╔══██╗╚██╗ ██╔╝");
    Serial.println("      █████╗  █████╗  ██████╔╝██║   ██║██║  ███╗███████║ ╚████╔╝ ");
    Serial.println("      ██╔══╝  ██╔══╝  ██╔═══╝ ██║   ██║██║   ██║██╔══██║  ╚██╔╝  ");
    Serial.println("      ███████╗███████╗██║     ╚██████╔╝╚██████╔╝██║  ██║   ██║   ");
    Serial.println("      ╚══════╝╚══════╝╚═╝     ╚═════╝  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ");
    Serial.printf("\n- - - ZERODAY CONTROLLER INITIALIZING | v%s - - -\n", FW_VERSION);

    setupWiFi();
    Serial.println("\n--- [ SYSTEM ONLINE ] ---");
}

void loop() {}