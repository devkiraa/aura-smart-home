#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <Firebase_ESP_Client.h>
#include <Preferences.h>
#include "firebase_config.h"

#define FW_VERSION "9.1-robust-log"
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
  Serial.printf("  > Fetching remote config...");

  if (Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "", documentPath.c_str(), "")) {
    JsonDocument doc;
    deserializeJson(doc, fbdo.payload().c_str());
    if (doc.containsKey("fields") && doc["fields"].containsKey("appliances")) {
      JsonArray array = doc["fields"]["appliances"]["arrayValue"]["values"];
      appliances.clear();
      for (JsonObject obj : array) {
        Appliance appliance;
        appliance.name = obj["mapValue"]["fields"]["name"]["stringValue"].as<String>();
        appliance.pin = obj["mapValue"]["fields"]["pin"]["integerValue"].as<int>();
        appliance.state = false;
        appliances.push_back(appliance);
        pinMode(appliance.pin, OUTPUT);
        digitalWrite(appliance.pin, LOW); // Active-high relays start OFF
      }
      Serial.printf("%-45s [ OK ]\n", "");
      Serial.printf("    > Found %d configured appliances.\n", appliances.size());
    }
  } else {
    Serial.printf("%-45s [FAIL]\n", "");
    Serial.println("    > Firestore Error: " + fbdo.errorReason());
  }
}

void applianceStreamCallback(FirebaseStream data) {
    digitalWrite(ONBOARD_LED, HIGH);
    String pinStr = data.dataPath().substring(1, data.dataPath().lastIndexOf('/'));
    int pin = pinStr.toInt();
    bool newState = (data.stringData() == "ON");
    for (auto& appliance : appliances) {
        if (appliance.pin == pin) {
            appliance.state = newState;
            digitalWrite(appliance.pin, newState);
            Serial.printf("[COMMAND] Remote Toggle: Pin %d -> %s\n", pin, newState ? "ON" : "OFF");
            break;
        }
    }
    delay(50);
    digitalWrite(ONBOARD_LED, LOW);
}

void commandStreamCallback(FirebaseStream data) {
  if (data.dataTypeEnum() == fb_esp_rtdb_data_type_string && data.stringData() == "REBOOT") {
    Serial.println("[COMMAND] Remote Reboot Received. Restarting...");
    Firebase.RTDB.deleteNode(&fbdo, data.streamPath());
    delay(1000);
    ESP.restart();
  }
}

void streamTimeoutCallback(bool timeout) {
  if (timeout) Serial.println("[!] RTDB Stream timeout.");
}

void setupFirebase() {
    Serial.println("==================================================");
    Serial.println("INITIALIZING CLOUD SERVICES");
    Serial.println("==================================================");
    config.api_key = API_KEY;
    config.database_url = DATABASE_URL;
    config.signer.test_mode = true;
    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);

    Serial.printf("%-45s", "  > Authenticating with Firebase...");
    unsigned long startMillis = millis();
    while (!Firebase.ready() && millis() - startMillis < 10000) {
        digitalWrite(ONBOARD_LED, HIGH); delay(50);
        digitalWrite(ONBOARD_LED, LOW); delay(50);
        digitalWrite(ONBOARD_LED, HIGH); delay(50);
        digitalWrite(ONBOARD_LED, LOW); delay(850);
    }

    if (!Firebase.ready()) { Serial.println(" [FAIL]"); return; }
    
    firebaseReady = true;
    Serial.println(" [ OK ]");
    
    loadConfigurationFromFirestore();
    
    Serial.printf("%-45s", "  > Initializing Realtime Database streams...");
    String commandPath = "devices/" + WiFi.macAddress() + "/command";
    Firebase.RTDB.beginStream(&command_stream, commandPath.c_str());
    Firebase.RTDB.setStreamCallback(&command_stream, commandStreamCallback, streamTimeoutCallback);
    
    String appliancesPath = "devices/" + WiFi.macAddress() + "/appliances";
    Firebase.RTDB.beginStream(&appliance_stream, appliancesPath.c_str());
    Firebase.RTDB.setStreamCallback(&appliance_stream, applianceStreamCallback, streamTimeoutCallback);
    Serial.println(" [ OK ]");
    
    Serial.printf("%-45s", "  > Reporting device status to cloud...");
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
    
    if (Firebase.RTDB.setJSON(&fbdo, device_path.c_str(), &status_json)) {
      Serial.println(" [ OK ]");
    } else {
      Serial.println(" [FAIL]");
    }
}

void startWebServer() {
  Serial.println("==================================================");
  Serial.println("STARTING LOCAL WEB SERVER");
  Serial.println("==================================================");
  server.on("/toggle", HTTP_GET, [] (AsyncWebServerRequest *request) {
    if (request->hasParam("pin")) {
      digitalWrite(ONBOARD_LED, HIGH);
      int pin = request->getParam("pin")->value().toInt();
      for (auto& appliance : appliances) {
        if (appliance.pin == pin) {
          appliance.state = !appliance.state;
          digitalWrite(appliance.pin, appliance.state);
          Firebase.RTDB.setString(&fbdo, "devices/" + WiFi.macAddress() + "/appliances/" + String(pin) + "/state", appliance.state ? "ON" : "OFF");
          request->send(200, "text/plain", appliance.state ? "ON" : "OFF");
          delay(50);
          digitalWrite(ONBOARD_LED, LOW);
          return;
        }
      }
    }
    request->send(400, "text/plain", "Missing or invalid pin parameter");
  });
  server.begin();
  Serial.printf("%-45s [ OK ]\n", "  > Server listening on port 80");
}

void setupWiFi() {
    Serial.println("==================================================");
    Serial.println("INITIALIZING NETWORK INTERFACE");
    Serial.println("==================================================");
    preferences.begin("wifi-creds", true);
    String saved_ssid = preferences.getString("ssid", "");
    String saved_pass = preferences.getString("password", "");
    preferences.end();
    
    if (saved_ssid.length() == 0) {
      Serial.printf("%-45s [FAIL]\n", "  > No Wi-Fi credentials found.");
      return;
    }

    WiFi.begin(saved_ssid.c_str(), saved_pass.c_str());
    Serial.printf("%-45s", ("  > Connecting to " + saved_ssid).c_str());
    
    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < 40) {
        digitalWrite(ONBOARD_LED, HIGH); delay(75);
        digitalWrite(ONBOARD_LED, LOW); delay(75);
        Serial.print(".");
        retries++;
    }
    
    if (WiFi.status() == WL_CONNECTED) {
        digitalWrite(ONBOARD_LED, LOW);
        Serial.println(" [ OK ]");
        Serial.printf("    > IP Address: %s\n", WiFi.localIP().toString().c_str());
        setupFirebase(); 
        startWebServer(); 
    } else {
        Serial.println(" [FAIL]");
        for (int i=0; i<3; i++) {
          digitalWrite(ONBOARD_LED, HIGH); delay(400);
          digitalWrite(ONBOARD_LED, LOW); delay(400);
        }
    }
}

void setup() {
    Serial.begin(115200);
    pinMode(ONBOARD_LED, OUTPUT);
    digitalWrite(ONBOARD_LED, LOW); 

    Serial.println("\n\n");
Serial.println("███████╗███████╗██████╗  ██████╗  █████╗ ██╗   ██╗");
Serial.println("╚══███╔╝██╔════╝██╔══██╗██╔═══██╗██╔══██╗╚██╗ ██╔╝");
Serial.println("  ███╔╝ █████╗  ██████╔╝██║   ██║███████║ ╚████╔╝ ");
Serial.println(" ███╔╝  ██╔══╝  ██╔══██╗██║   ██║██╔══██║  ╚██╔╝  ");
Serial.println("███████╗███████╗██║  ██║╚██████╔╝██║  ██║   ██║   ");
Serial.println("╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ");
Serial.printf("\n- - - ZERODAY CONTROLLER INITIALIZING | v%s - - -\n", FW_VERSION);
Serial.printf("      MAC: %s\n\n", WiFi.macAddress().c_str());

    
    setupWiFi();
    Serial.println("\n==================================================");
    Serial.println("SYSTEM ONLINE AND READY");
    Serial.println("==================================================");
}

void loop() {}