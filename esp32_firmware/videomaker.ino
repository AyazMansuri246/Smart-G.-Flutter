
#include "esp_camera.h"
#include <WiFi.h>
#include <WebServer.h>
#include <stdio.h>
#include <string.h>
#include "FS.h"
#include "SD_MMC.h"

// Camera model
#define CAMERA_MODEL_AI_THINKER 
#include "camera_pins.h"

// WiFi Config
const char* ssid = "ESP32_CAM_VIDEO";
const char* password = "12345678";

WebServer server(80);

// Video Settings
const int MAX_VIDEO_TIME = 30; // seconds
const int FPS = 10;
const int FRAME_INTERVAL = 1000 / FPS;

// Pins
const int TOUCH_PIN = 13;

// State
bool isRecording = false;
unsigned long recordingStartTime = 0;
unsigned long lastFrameTime = 0;
int frameCount = 0;
char currentFileName[64];
File videoFile;
File indexFile;
uint32_t movi_size = 0;

// AVI Index Entry
struct avi_idx1_entry {
  uint32_t chunk_id;
  uint32_t flags;
  uint32_t offset;
  uint32_t size;
};

// Helper for CORS
void sendCORSResponse(int code, const char* content_type, const String& content) {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  server.send(code, content_type, content);
}

// Server Handlers
void handleListVideos() {
  File root = SD_MMC.open("/Videos");
  if (!root) {
    SD_MMC.mkdir("/Videos");
    sendCORSResponse(200, "application/json", "[]");
    return;
  }

  String json = "[";
  File file = root.openNextFile();
  bool first = true;
  while (file) {
    if (!file.isDirectory() && String(file.name()).endsWith(".avi")) {
      if (!first) json += ",";
      String name = String(file.name());
      int lastSlash = name.lastIndexOf('/');
      json += "\"" + (lastSlash != -1 ? name.substring(lastSlash + 1) : name) + "\"";
      first = false;
    }
    file = root.openNextFile();
  }
  json += "]";
  sendCORSResponse(200, "application/json", json);
}

void handleGetVideo() {
  if (!server.hasArg("name")) {
    sendCORSResponse(400, "text/plain", "Missing name");
    return;
  }
  String path = "/Videos/" + server.arg("name");
  if (!SD_MMC.exists(path)) {
    sendCORSResponse(404, "text/plain", "Not found");
    return;
  }
  File file = SD_MMC.open(path);
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.streamFile(file, "video/x-msvideo");
  file.close();
}

void handleDeleteVideo() {
  if (!server.hasArg("name")) {
    sendCORSResponse(400, "text/plain", "Missing name");
    return;
  }
  String path = "/Videos/" + server.arg("name");
  if (SD_MMC.remove(path)) {
    sendCORSResponse(200, "text/plain", "Deleted");
  } else {
    sendCORSResponse(500, "text/plain", "Delete failed");
  }
}

// Image handlers (compatible with other sections)
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
      String name = String(file.name());
      int lastSlash = name.lastIndexOf('/');
      json += "\"" + (lastSlash != -1 ? name.substring(lastSlash + 1) : name) + "\"";
      first = false;
    }
    file = root.openNextFile();
  }
  json += "]";
  sendCORSResponse(200, "application/json", json);
}

void handleGetImage() {
  if (!server.hasArg("name")) {
    sendCORSResponse(400, "text/plain", "Missing name");
    return;
  }
  String path = "/Images/" + server.arg("name");
  File file = SD_MMC.open(path);
  if (!file) {
    sendCORSResponse(404, "text/plain", "Not found");
    return;
  }
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.streamFile(file, "image/jpeg");
  file.close();
}

void setup() {
  Serial.begin(115200);
  
  // Camera Setup
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
  config.xclk_freq_hz = 10000000; // Lowered to 10MHz for stability
  config.pixel_format = PIXFORMAT_JPEG;

  if(psramFound()){
    config.frame_size = FRAMESIZE_VGA;
    config.jpeg_quality = 12; // Slightly lower quality (higher number) to save bandwidth
    config.fb_count = 4;      // Increased buffer count to prevent OVF
  } else {
    config.frame_size = FRAMESIZE_SVGA;
    config.jpeg_quality = 12;
    config.fb_count = 1;
  }

  esp_camera_init(&config);

  // SD Card 1-bit mode (frees GPIO 13)
  if(!SD_MMC.begin("/sdcard", true)){
    Serial.println("SD MMC Fail");
  }
  if (!SD_MMC.exists("/Videos")) SD_MMC.mkdir("/Videos");
  if (!SD_MMC.exists("/Images")) SD_MMC.mkdir("/Images");

  // WiFi AP
  WiFi.softAP(ssid, password);
  Serial.print("AP IP: "); Serial.println(WiFi.softAPIP());

  // Server
  server.on("/videos", HTTP_GET, handleListVideos);
  server.on("/video", HTTP_GET, handleGetVideo);
  server.on("/video/delete", HTTP_GET, handleDeleteVideo);
  server.on("/images", HTTP_GET, handleListImages);
  server.on("/image", HTTP_GET, handleGetImage);
  server.begin();

  pinMode(TOUCH_PIN, INPUT);
  pinMode(33, OUTPUT);
  digitalWrite(33, HIGH); // LED OFF initially
  Serial.println("System Ready. Long press GPIO13 to record.");
}

void startRecording() {
  Serial.println("Starting Recording...");
  server.stop(); // Stop server to save CPU
  digitalWrite(33, LOW); // Onboard LED ON (Active Low on most ESP32-CAM)
  // Find dynamic filename
  int n = 0;
  while(true) {
    sprintf(currentFileName, "/Videos/vid_%03d.avi", n);
    if (!SD_MMC.exists(currentFileName)) break;
    n++;
  }

  videoFile = SD_MMC.open(currentFileName, FILE_WRITE);
  indexFile = SD_MMC.open("/idx.tmp", FILE_WRITE);

  // Placeholder for AVI header (250 bytes)
  uint8_t buf[250];
  memset(buf, 0, 250);
  videoFile.write(buf, 250);

  movi_size = 0;
  frameCount = 0;
  recordingStartTime = millis();
  isRecording = true;
}

void stopRecording() {
  isRecording = false;
  Serial.println("Stopping Recording...");
  digitalWrite(33, HIGH); // Onboard LED OFF

  indexFile.close();
  indexFile = SD_MMC.open("/idx.tmp", FILE_READ);

  // Write idx1 chunk
  uint32_t idx1_id = 0x31786469; // 'idx1'
  uint32_t idx1_size = frameCount * sizeof(struct avi_idx1_entry);
  videoFile.write((uint8_t*)&idx1_id, 4);
  videoFile.write((uint8_t*)&idx1_size, 4);

  while (indexFile.available()) {
    uint8_t b;
    indexFile.read(&b, 1);
    videoFile.write(b);
  }
  indexFile.close();
  SD_MMC.remove("/idx.tmp");

  // Write AVI Header
  uint32_t total_size = videoFile.size();
  videoFile.seek(0, SeekSet);

  uint32_t riff_size = total_size - 8;
  videoFile.write((uint8_t*)"RIFF", 4);
  videoFile.write((uint8_t*)&riff_size, 4);
  videoFile.write((uint8_t*)"AVI ", 4);
  
  videoFile.write((uint8_t*)"LIST", 4);
  uint32_t hdrl_size = 172; 
  videoFile.write((uint8_t*)&hdrl_size, 4);
  videoFile.write((uint8_t*)"hdrl", 4);
  
  videoFile.write((uint8_t*)"avih", 4);
  uint32_t avih_size = 56;
  videoFile.write((uint8_t*)&avih_size, 4);
  uint32_t us_per_frame = 1000000 / FPS;
  videoFile.write((uint8_t*)&us_per_frame, 4);
  uint32_t zero = 0;
  videoFile.write((uint8_t*)&zero, 4); // max bytes
  videoFile.write((uint8_t*)&zero, 4); // padding
  uint32_t flags = 0x10; videoFile.write((uint8_t*)&flags, 4); 
  videoFile.write((uint8_t*)&frameCount, 4);
  videoFile.write((uint8_t*)&zero, 4); // initial frames
  uint32_t streams = 1; videoFile.write((uint8_t*)&streams, 4);
  uint32_t buf_size = 102400; videoFile.write((uint8_t*)&buf_size, 4);
  uint32_t width = 640; videoFile.write((uint8_t*)&width, 4);
  uint32_t height = 480; videoFile.write((uint8_t*)&height, 4);
  uint32_t res[4] = {0,0,0,0}; videoFile.write((uint8_t*)res, 16);

  videoFile.write((uint8_t*)"LIST", 4);
  uint32_t strl_size = 108; videoFile.write((uint8_t*)&strl_size, 4);
  videoFile.write((uint8_t*)"strl", 4);
  videoFile.write((uint8_t*)"strh", 4);
  uint32_t strh_size = 56; videoFile.write((uint8_t*)&strh_size, 4);
  videoFile.write((uint8_t*)"vids", 4);
  videoFile.write((uint8_t*)"MJPG", 4);
  videoFile.write((uint8_t*)&zero, 20); // various fields
  uint32_t scale = 1; videoFile.write((uint8_t*)&scale, 4);
  uint32_t rate = FPS; videoFile.write((uint8_t*)&rate, 4);
  videoFile.write((uint8_t*)&zero, 4); // start
  videoFile.write((uint8_t*)&frameCount, 4);
  videoFile.write((uint8_t*)&buf_size, 4);
  int32_t qual = -1; videoFile.write((uint8_t*)&qual, 4);
  videoFile.write((uint8_t*)&zero, 12);

  videoFile.write((uint8_t*)"strf", 4);
  uint32_t strf_size = 40; videoFile.write((uint8_t*)&strf_size, 4);
  uint32_t biSize = 40; videoFile.write((uint8_t*)&biSize, 4);
  videoFile.write((uint8_t*)&width, 4);
  videoFile.write((uint8_t*)&height, 4);
  uint16_t planes = 1; videoFile.write((uint8_t*)&planes, 2);
  uint16_t bits = 24; videoFile.write((uint8_t*)&bits, 2);
  videoFile.write((uint8_t*)"MJPG", 4);
  uint32_t imgSize = width * height * 3; videoFile.write((uint8_t*)&imgSize, 4);
  videoFile.write((uint8_t*)&zero, 16);

  videoFile.seek(224, SeekSet);
  videoFile.write((uint8_t*)"LIST", 4);
  uint32_t movi_list_size = movi_size + 4;
  videoFile.write((uint8_t*)&movi_list_size, 4);
  videoFile.write((uint8_t*)"movi", 4);

  videoFile.close();
  Serial.printf("Video Saved: %s\n", currentFileName);
  
  server.begin(); // Restart server
}

unsigned long touchStartTime = 0;
bool touchActive = false;

void loop() {
  if (!isRecording) {
    server.handleClient();
  }

  // Touch Logic for Long Press (2-3 seconds)
  // touchRead normally returns high values (e.g. 50+) and lower when touched.
  // Since we have a 10k internal pull-up on GPIO 13 in SD 1-bit mode, 
  // we use touchRead(TOUCH_PIN) or digitalRead(TOUCH_PIN).
  // touchRead is better for capacitive.
  int val = touchRead(TOUCH_PIN);
  
  if (val < 40) { // Threshold for touch
    if (!touchActive) {
      touchActive = true;
      touchStartTime = millis();
    } else {
      unsigned long duration = millis() - touchStartTime;
      if (duration > 2000 && duration < 2500) { // Specific window to trigger
         // We can visual feedback here if needed
      }
    }
  } else {
    if (touchActive) {
      unsigned long duration = millis() - touchStartTime;
      if (duration >= 2000) { // Long press threshold
        if (!isRecording) startRecording();
        else stopRecording();
      }
      touchActive = false;
    }
  }

  // Recording Logic
  if (isRecording) {
    if (millis() - recordingStartTime > MAX_VIDEO_TIME * 1000) {
      stopRecording();
    } else if (millis() - lastFrameTime >= FRAME_INTERVAL) {
      lastFrameTime = millis();
      camera_fb_t * fb = esp_camera_fb_get();
      if (fb) {
        uint32_t dc_id = 0x63643030; // '00dc'
        uint32_t sz = fb->len;
        uint32_t pad = (4 - (sz % 4)) % 4;
        uint32_t total_sz = sz + pad;

        videoFile.write((uint8_t*)&dc_id, 4);
        videoFile.write((uint8_t*)&total_sz, 4);
        videoFile.write(fb->buf, fb->len);
        if (pad > 0) { uint8_t z = 0; for(int p=0; p<pad; p++) videoFile.write(&z, 1); }

        struct avi_idx1_entry entry;
        entry.chunk_id = dc_id;
        entry.flags = 0x10;
        entry.offset = movi_size + 4;
        entry.size = sz;
        indexFile.write((uint8_t*)&entry, sizeof(entry));

        movi_size += (8 + total_sz);
        frameCount++;
        esp_camera_fb_return(fb);
      }
    }
  }
}
