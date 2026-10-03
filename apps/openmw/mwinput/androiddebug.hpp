#ifndef OPENMW_MWINPUT_ANDROIDDEBUG_HPP
#define OPENMW_MWINPUT_ANDROIDDEBUG_HPP

#include <string>

namespace MWInput
{
    class ControllerManager;

    // OPENMW_ANDROID_051_DEBUG_CONTROL: ADB model-control surface
    // (scene census, activation results, menu focus, streaming telemetry,
    // on-device motor primitives, save loading). Hosted in
    // androiddebug.cpp; kept out of controllermanager.cpp so the earlier
    // patches' hunks keep applying and reversing against this tree.
    namespace AndroidDebug
    {
        // Per-frame work (servo motors, streaming, pending requests).
        // Called from InputManager::update on the engine thread.
        void tick(float dt, ControllerManager& controllerManager);

        // Record the outcome of one player activation attempt (called
        // from Player::activate); surfaced as `act=` in the state line.
        void noteActivate(const std::string& outcome);

        // Episode logger (OPENMW_DEBUG_EPISODE=1): append one input line
        // to openmw.log per controller event, for host-side capture.
        void noteInputAxis(int axis, float value);
        void noteInputButton(int button, bool down);
        bool episodeLoggingEnabled();

        // True when OPENMW_DEBUG_NO_IDLECAM is set in the environment:
        // isIdle() stays false so the Lua idle-orbit camera never engages.
        bool idleCamDisabled();
    }
}

#endif
