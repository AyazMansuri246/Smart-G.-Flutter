#include <WiFi.h>
#include <WebServer.h>
#include "esp_camera.h"
#include "FS.h"
#include "SD_MMC.h"

// ===================
// Select Camera Model
// ===================
#define CAMERA_MODEL_AI_THINKER
#include "camera_pins.h"

const char* ssid = "ESP32_CAM_AP";
const char* password = "12345678";

WebServer server(80);

// Helper to set CORS headers and send response
void sendCORSResponse(int code, const char* content_type, const String& content) {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  server.send(code, content_type, content);
}

// Wi-Fi Access Point
void setupWiFiAP() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ssid, password);
  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());
}

// SD Card Init
bool initSD() {
  if (!SD_MMC.begin()) {
    Serial.println("SD Card Mount Failed");
    return false;
  }
  Serial.println("SD Card Mounted");
  return true;
}

// Camera Init
void initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  
  if(psramFound()){
    config.frame_size = FRAMESIZE_UXGA;
    config.jpeg_quality = 10;
    config.fb_count = 2;
  } else {
    config.frame_size = FRAMESIZE_SVGA;
    config.jpeg_quality = 12;
    config.fb_count = 1;
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x", err);
  }
}

// List Images (/images)
void handleListImages() {
  File root = SD_MMC.open("/Images");
  if (!root) {
    sendCORSResponse(200, "application/json", "[]");
    return;
  }

  String json = "[";
  File file = root.openNextFile();
  bool first = true;

  while (file) {
    if (!file.isDirectory()) {
      if (!first) json += ",";
      json += "\"" + String(file.name()).substring(8) + "\""; 
      first = false;
    }
    file = root.openNextFile();
  }
  json += "]";
  sendCORSResponse(200, "application/json", json);
}

// Get Image (/image)
void handleGetImage() {
  if (!server.hasArg("name")) {
    sendCORSResponse(400, "text/plain", "Missing image name");
    return;
  }

  String path = "/Images/" + server.arg("name");
  File file = SD_MMC.open(path);

  if (!file) {
    sendCORSResponse(404, "text/plain", "Image not found");
    return;
  }

  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.streamFile(file, "image/jpeg");
  file.close();
}

void setup() {
  Serial.begin(115200);
  initCamera();
  initSD();
  setupWiFiAP();

  server.on("/images", HTTP_GET, handleListImages);
  server.on("/image", HTTP_GET, handleGetImage);
  
  // Handle CORS preflight
  server.onNotFound([]() {
    if (server.method() == HTTP_OPTIONS) {
      server.sendHeader("Access-Control-Allow-Origin", "*");
      server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
      server.send(200, "text/plain", "OK");
    } else {
      server.send(404, "text/plain", "Not Found");
    }
  });

  server.begin();
  Serial.println("Server started");
}

void loop() {
  server.handleClient();
}
