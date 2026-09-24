#ifndef stderr
int stderr = 0; // Hack: fix linker error
#endif

#include "SDL_main.h"
#include "mwbase/environment.hpp"
#include "mwbase/windowmanager.hpp"
#include <SDL_events.h>
#include <SDL_gamecontroller.h>
#include <SDL_hints.h>
#include <SDL_mouse.h>

#include <osg/GraphicsContext>
#include <osg/OperationThread>
#include <osgViewer/Viewer>

#include <algorithm>

/*******************************************************************************
 Functions called by JNI
 *******************************************************************************/
#include <jni.h>

/* Called before  to initialize JNI bindings  */

extern void SDL_Android_Init(JNIEnv* env, jclass cls);
extern int argcData;
extern const char** argvData;
void releaseArgv();

extern "C" int Java_org_libsdl_app_SDLActivity_getMouseX(JNIEnv* env, jclass cls, jobject obj)
{
    int ret = 0;
    SDL_GetMouseState(&ret, nullptr);
    return ret;
}

extern "C" int Java_org_libsdl_app_SDLActivity_getMouseY(JNIEnv* env, jclass cls, jobject obj)
{
    int ret = 0;
    SDL_GetMouseState(nullptr, &ret);
    return ret;
}

extern "C" int Java_org_libsdl_app_SDLActivity_isMouseShown(JNIEnv* env, jclass cls, jobject obj)
{
    return SDL_ShowCursor(SDL_QUERY);
}

// SDL 2.30 no longer exports SDL_SendMouseMotion/SDL_SendMouseButton or
// Android_Window; inject synthetic events through the public SDL_PushEvent.
static SDL_Window* omwWindow()
{
    SDL_Window* win = SDL_GetKeyboardFocus();
    if (!win)
        win = SDL_GetWindowFromID(1);
    return win;
}

extern "C" void Java_org_libsdl_app_SDLActivity_sendRelativeMouseMotion(JNIEnv* env, jclass cls, int x, int y)
{
    SDL_Window* win = omwWindow();
    if (!win)
        return;

    static int px = 0;
    static int py = 0;
    int w = 0;
    int h = 0;
    SDL_GetWindowSize(win, &w, &h);
    px = std::min(std::max(px + x, 0), w > 0 ? w - 1 : 0);
    py = std::min(std::max(py + y, 0), h > 0 ? h - 1 : 0);

    SDL_Event ev;
    SDL_memset(&ev, 0, sizeof(ev));
    ev.type = SDL_MOUSEMOTION;
    ev.motion.windowID = SDL_GetWindowID(win);
    ev.motion.x = px;
    ev.motion.y = py;
    ev.motion.xrel = x;
    ev.motion.yrel = y;
    SDL_PushEvent(&ev);
}

extern "C" void Java_org_libsdl_app_SDLActivity_sendMouseButton(JNIEnv* env, jclass cls, int state, int button)
{
    SDL_Window* win = omwWindow();
    if (!win)
        return;

    SDL_Event ev;
    SDL_memset(&ev, 0, sizeof(ev));
    ev.type = state ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
    ev.button.windowID = SDL_GetWindowID(win);
    ev.button.button = button;
    ev.button.state = state ? SDL_PRESSED : SDL_RELEASED;
    ev.button.clicks = 1;
    SDL_PushEvent(&ev);
}

extern "C" int Java_org_libsdl_app_SDLActivity_nativeInit(JNIEnv* env, jclass cls, jobject obj)
{
    setenv("OPENMW_DECOMPRESS_TEXTURES", "1", 1);

    // On Android, we use a virtual controller with guid="Virtual"
    SDL_GameControllerAddMapping(
        "5669727475616c000000000000000000,Virtual,a:b0,b:b1,back:b15,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,"
        "guide:b16,leftshoulder:b6,leftstick:b13,lefttrigger:a5,leftx:a0,lefty:a1,rightshoulder:b7,rightstick:b14,"
        "righttrigger:a4,rightx:a2,righty:a3,start:b11,x:b3,y:b4");

    // OPENMW_ANDROID_051_RUNTIME_BASELINE
    // Do not stall the SDL thread while Android is paused. Surface ownership is
    // coordinated explicitly below with OSG's GraphicsContext operation queue.
    SDL_SetHint(SDL_HINT_ANDROID_BLOCK_ON_PAUSE, "0");
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");

    return 0;
}

extern osg::ref_ptr<osgViewer::Viewer> g_viewer;
extern bool g_androidWindowManagerReady;
static osg::GraphicsContext* g_androidContext = nullptr;

class CtxReleaseOperation : public osg::Operation
{
public:
    CtxReleaseOperation()
        : osg::Operation("OpenMW Android release GL context", false)
    {
    }

    void operator()(osg::Object*) override
    {
        if (g_androidContext)
            g_androidContext->releaseContext();
    }
};

class CtxAcquireOperation : public osg::Operation
{
public:
    CtxAcquireOperation()
        : osg::Operation("OpenMW Android acquire GL context", false)
    {
    }

    void operator()(osg::Object*) override
    {
        if (g_androidContext)
            g_androidContext->makeCurrent();
    }
};

extern "C" void Java_org_libsdl_app_SDLActivity_omwSurfaceDestroyed(JNIEnv*, jclass)
{
    if (!g_viewer)
        return;

    g_androidContext = g_viewer->getCamera()->getGraphicsContext();
    if (g_androidContext)
        g_androidContext->add(new CtxReleaseOperation());

    if (g_androidWindowManagerReady)
        MWBase::Environment::get().getWindowManager()->windowVisibilityChange(false);
}

extern "C" void Java_org_libsdl_app_SDLActivity_omwSurfaceRecreated(JNIEnv*, jclass)
{
    if (!g_viewer)
        return;

    g_androidContext = g_viewer->getCamera()->getGraphicsContext();
    if (g_androidContext)
        g_androidContext->add(new CtxAcquireOperation());

    if (g_androidWindowManagerReady)
        MWBase::Environment::get().getWindowManager()->windowVisibilityChange(true);
}
