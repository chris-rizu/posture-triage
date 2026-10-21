// BLE peripheral (NimBLE-Arduino 2.x): one service, three characteristics.
// UUIDs and message formats are in lib/core/src/protocol.h and docs/BLE_PROTOCOL.md.
#pragma once
#include <Arduino.h>
#include <NimBLEDevice.h>
#include "protocol.h"

class BleLink {
 public:
  static constexpr int kCmdMax = 320;

  void begin() {
    queue_ = xQueueCreate(6, kCmdMax);
    NimBLEDevice::init(PT_DEVICE_NAME);
    NimBLEDevice::setMTU(517);
    server_ = NimBLEDevice::createServer();
    server_->setCallbacks(&serverCb_);
    NimBLEService* svc = server_->createService(PT_SERVICE_UUID);
    meas_ = svc->createCharacteristic(PT_MEASUREMENT_UUID, NIMBLE_PROPERTY::NOTIFY);
    result_ = svc->createCharacteristic(PT_RESULT_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    cmd_ = svc->createCharacteristic(PT_COMMAND_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
    cmdCb_.queue = queue_;
    cmd_->setCallbacks(&cmdCb_);
    server_->start();
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(PT_SERVICE_UUID);
    adv->setName(PT_DEVICE_NAME);
    adv->enableScanResponse(true);
    adv->start();
  }

  bool connected() const { return server_ && server_->getConnectedCount() > 0; }

  void sendMeasurement(const uint8_t* data, int len) {
    if (!connected()) return;
    meas_->setValue(data, len);
    meas_->notify();
  }

  void sendJson(const char* json) {
    result_->setValue((const uint8_t*)json, strlen(json));
    if (connected()) result_->notify();
  }

  // Pops one received command into buf; returns false if none is waiting.
  bool nextCommand(char* buf) { return queue_ && xQueueReceive(queue_, buf, 0) == pdTRUE; }

 private:
  struct ServerCb : NimBLEServerCallbacks {
    void onConnect(NimBLEServer* s, NimBLEConnInfo& info) override {
      // ask for a short connection interval (15-30 ms) so the 5 Hz stream is smooth
      s->updateConnParams(info.getConnHandle(), 12, 24, 0, 400);
    }
    void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override { NimBLEDevice::startAdvertising(); }
  };
  struct CmdCb : NimBLECharacteristicCallbacks {
    QueueHandle_t queue = nullptr;
    void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
      char buf[kCmdMax];
      std::string v = c->getValue();
      size_t n = v.size() < kCmdMax - 1 ? v.size() : kCmdMax - 1;
      memcpy(buf, v.data(), n);
      buf[n] = 0;
      xQueueSend(queue, buf, 0);
    }
  };

  NimBLEServer* server_ = nullptr;
  NimBLECharacteristic* meas_ = nullptr;
  NimBLECharacteristic* result_ = nullptr;
  NimBLECharacteristic* cmd_ = nullptr;
  QueueHandle_t queue_ = nullptr;
  ServerCb serverCb_;
  CmdCb cmdCb_;
};
