#ifndef OPENMW_MWRENDER_DEBUGMARKERS_HPP
#define OPENMW_MWRENDER_DEBUGMARKERS_HPP

#include <osg/ref_ptr>

namespace osg
{
    class Group;
}

namespace MWRender
{
    // OPENMW_ANDROID_051_DEBUG_CONTROL: colored x-ray markers over nearby
    // activatable objects (doors orange, containers green, live actors
    // cyan) so a vision model can spot targets by color instead of
    // recognizing Morrowind objects in dark frames. Enabled with
    // OPENMW_DEBUG_MARKERS=1; rebuilt in place every update().
    class DebugMarkers
    {
    public:
        explicit DebugMarkers(osg::Group* root);
        ~DebugMarkers();

        void update();

    private:
        osg::ref_ptr<osg::Group> mRoot;
        osg::ref_ptr<osg::Group> mGroup;
        double mLastUpdate = 0.f;
    };
}

#endif
