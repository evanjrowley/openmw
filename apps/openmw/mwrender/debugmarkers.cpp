#include "debugmarkers.hpp"

#include "../mwbase/environment.hpp"
#include "../mwbase/mechanicsmanager.hpp"
#include "../mwbase/world.hpp"
#include "../mwmechanics/creaturestats.hpp"
#include "../mwworld/cellstore.hpp"
#include "../mwworld/class.hpp"
#include "../mwworld/refdata.hpp"

#include <components/esm3/loadcont.hpp>
#include <components/esm3/loaddoor.hpp>

#include <osg/Depth>
#include <osg/Geode>
#include <osg/Group>
#include <osg/MatrixTransform>
#include <osg/ShapeDrawable>

#include <chrono>
#include <cmath>
#include <memory>
#include <vector>

namespace MWRender
{
    namespace
    {
        constexpr double sUpdatePeriod = 0.5; // seconds between rebuilds
        constexpr float sRadius = 1500.f;     // game units around the player
        constexpr float sMarkerSize = 12.f;

        osg::ref_ptr<osg::Depth> makeAlwaysDepth()
        {
            // X-ray: draw over the world so markers stay readable through
            // walls (the whole point in dark interiors).
            auto* depth = new osg::Depth(osg::Depth::ALWAYS, 0, 0, false);
            depth->setWriteMask(false);
            return depth;
        }

        void addMarker(osg::Group* group, osg::StateSet* sharedState,
            const osg::Vec3f& pos, float radius, osg::Vec4f color)
        {
            auto* geode = new osg::Geode;
            auto* drawable = new osg::ShapeDrawable(
                new osg::Sphere(osg::Vec3f(0.f, 0.f, 0.f), radius));
            // OpenMW's shader pipeline follows the drawable's vertex colors,
            // not fixed-function materials — color the geometry itself.
            drawable->setColor(color);
            drawable->setStateSet(sharedState);
            geode->addChild(drawable);
            auto* xform = new osg::MatrixTransform(
                osg::Matrix::translate(pos));
            xform->addChild(geode);
            group->addChild(xform);
        }
    }

    DebugMarkers::DebugMarkers(osg::Group* root)
        : mRoot(root)
        , mGroup(new osg::Group)
    {
        mGroup->setName("android_debug_markers");
        mRoot->addChild(mGroup);
    }

    DebugMarkers::~DebugMarkers()
    {
        if (mRoot.valid() && mGroup.valid())
            mRoot->removeChild(mGroup);
    }

    void DebugMarkers::update()
    {
        const double now = std::chrono::duration<double>(
            std::chrono::steady_clock::now().time_since_epoch())
                               .count();
        if (now - mLastUpdate < sUpdatePeriod)
            return;
        mLastUpdate = now;

        const MWWorld::Ptr player = MWBase::Environment::get().getWorld()->getPlayerPtr();
        if (player.isEmpty() || player.getCell() == nullptr
            || player.getCell()->getCell() == nullptr)
            return;
        const ESM::Position& pos = player.getRefData().getPosition();
        const osg::Vec3f origin(pos.pos[0], pos.pos[1], pos.pos[2]);

        // Shared depth state is rebuilt with the group each cycle to keep
        // the lifetime story trivial; colors go on the drawables themselves
        // (OpenMW's shader pipeline follows vertex colors, not materials).
        static osg::ref_ptr<osg::Depth> depth = makeAlwaysDepth();

        auto makeState = [&]()
        {
            auto* state = new osg::StateSet;
            state->setAttributeAndModes(depth, osg::StateAttribute::OVERRIDE);
            state->setMode(GL_BLEND, osg::StateAttribute::ON | osg::StateAttribute::OVERRIDE);
            return state;
        };
        static osg::ref_ptr<osg::StateSet> sharedState = makeState();

        mGroup->removeChildren(0, mGroup->getNumChildren());

        MWBase::World* world = MWBase::Environment::get().getWorld();

        player.getCell()->forEachType<ESM::Door>([&](const MWWorld::Ptr& door)
        {
            const float* dp = door.getRefData().getPosition().pos;
            const osg::Vec3f d(dp[0], dp[1], dp[2]);
            if ((d - origin).length() <= sRadius)
                addMarker(mGroup, sharedState, d + osg::Vec3f(0.f, 0.f, 64.f),
                    sMarkerSize, osg::Vec4f(1.f, 0.55f, 0.f, 0.6f));
            return true;
        });

        player.getCell()->forEachType<ESM::Container>([&](const MWWorld::Ptr& container)
        {
            const float* cp = container.getRefData().getPosition().pos;
            const osg::Vec3f c(cp[0], cp[1], cp[2]);
            if ((c - origin).length() <= sRadius)
                addMarker(mGroup, sharedState, c + osg::Vec3f(0.f, 0.f, 48.f),
                    sMarkerSize * 0.75f, osg::Vec4f(0.2f, 1.f, 0.3f, 0.6f));
            return true;
        });

        std::vector<MWWorld::Ptr> actors;
        MWBase::Environment::get().getMechanicsManager()->getActorsInRange(origin, sRadius, actors);
        for (const MWWorld::Ptr& actor : actors)
        {
            if (actor == player || actor.isEmpty())
                continue;
            const auto& stats = actor.getClass().getCreatureStats(actor);
            if (stats.isDead())
                continue;
            const float* ap = actor.getRefData().getPosition().pos;
            addMarker(mGroup, sharedState, osg::Vec3f(ap[0], ap[1], ap[2] + 80.f),
                sMarkerSize, osg::Vec4f(0.3f, 0.8f, 1.f, 0.6f));
        }
    }
}
