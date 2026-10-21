// Glue between the virtual wearer and the Device: moves the wearer into the
// forward bend when a BEND trial starts and handles the "SIM ..." commands.
// Used by the SIMULATE firmware build and by the unit tests.
#pragma once
#include <ctype.h>
#include <string.h>
#include "protocol.h"
#include "simulator.h"

namespace pt {

class SimDriver {
 public:
  explicit SimDriver(uint32_t seed = 7u) : sim(seed) {}
  WearerSim sim;

  // In automatic mode the wearer bends forward when a BEND trial starts and
  // straightens up after it. "SIM POSE <x>" switches to manual; "SIM POSE AUTO" back.
  void onState(DevState s) {
    if (manual_) return;
    if (s == ST_BEND) { sim.setPose(POSE_BEND, 0.8f); autoBend_ = true; }
    else if (autoBend_) { sim.setPose(POSE_STAND, 1.5f); autoBend_ = false; }
  }

  // SIM PROFILE <healthy|rounded|asymmetric|scoliotic>
  // SIM POSE <stand|bend|slouch|auto>
  // SIM FIDGET <on|off>      SIM NOISE <on|off>
  bool command(const char* arg) {
    char w1[16] = {0}, w2[24] = {0};
    if (sscanf(arg, "%15s %23s", w1, w2) != 2) return false;
    lower(w1); lower(w2);
    if (!strcmp(w1, "profile")) {
      const Profile* p = findProfile(w2);
      if (!p) return false;
      sim.setProfile(*p);
      return true;
    }
    if (!strcmp(w1, "pose")) {
      if (!strcmp(w2, "auto")) { manual_ = false; sim.setPose(POSE_STAND); return true; }
      if (!strcmp(w2, "stand")) sim.setPose(POSE_STAND);
      else if (!strcmp(w2, "bend")) sim.setPose(POSE_BEND);
      else if (!strcmp(w2, "slouch")) sim.setPose(POSE_SLOUCH);
      else return false;
      autoBend_ = false;
      manual_ = true;
      return true;
    }
    bool on = !strcmp(w2, "on");
    if (!on && strcmp(w2, "off")) return false;
    if (!strcmp(w1, "fidget")) { sim.setFidget(on); return true; }
    if (!strcmp(w1, "noise")) { sim.setNoise(on); return true; }
    return false;
  }

 private:
  static void lower(char* s) { for (; *s; ++s) *s = (char)tolower((unsigned char)*s); }
  bool autoBend_ = false, manual_ = false;
};

}  // namespace pt
