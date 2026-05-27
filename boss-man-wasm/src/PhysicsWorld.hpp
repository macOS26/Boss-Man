#pragma once
#include <box2d/box2d.h>
#include "PhysicsCategories.hpp"

namespace bm {

class PhysicsWorld {
public:
    b2World world;
    b2Body* wallBody = nullptr;
    b2Body* workerBody = nullptr;
    std::vector<b2Body*> bossBodies;
    std::vector<b2Body*> pickupBodies;

    PhysicsWorld() : world(b2Vec2(0.0f, 0.0f)) {
        world.SetAllowSleeping(false);
    }

    void createWallBody(const std::vector<sf::Vector2f>& wallCenters, float tileSize) {
        if (wallBody) world.DestroyBody(wallBody);
        b2BodyDef def;
        def.type = b2_staticBody;
        wallBody = world.CreateBody(&def);
        for (auto& center : wallCenters) {
            b2PolygonShape shape;
            shape.SetAsBox(tileSize / 2.0f / 100.0f, tileSize / 2.0f / 100.0f,
                          b2Vec2(center.x / 100.0f, center.y / 100.0f), 0);
            b2FixtureDef fix;
            fix.shape = &shape;
            fix.filter.categoryBits = PhysicsCat::WALL;
            wallBody->CreateFixture(&fix);
        }
    }

    b2Body* createKinematicCircle(float x, float y, float radius, uint16 category, uint16 mask) {
        b2BodyDef def;
        def.type = b2_kinematicBody;
        def.position.Set(x / 100.0f, y / 100.0f);
        b2Body* body = world.CreateBody(&def);
        b2CircleShape shape;
        shape.m_radius = radius / 100.0f;
        b2FixtureDef fix;
        fix.shape = &shape;
        fix.filter.categoryBits = category;
        fix.filter.maskBits = mask;
        fix.isSensor = true;
        body->CreateFixture(&fix);
        return body;
    }

    // Box2D only generates contacts when at least one body in the pair is dynamic.
    // The worker collides with everything, so it must be dynamic; sensor + zero
    // gravity keeps it from getting any physical response (position is grid-driven).
    b2Body* createDynamicCircle(float x, float y, float radius, uint16 category, uint16 mask) {
        b2BodyDef def;
        def.type = b2_dynamicBody;
        def.position.Set(x / 100.0f, y / 100.0f);
        def.fixedRotation = true;
        def.gravityScale = 0.0f;
        b2Body* body = world.CreateBody(&def);
        b2CircleShape shape;
        shape.m_radius = radius / 100.0f;
        b2FixtureDef fix;
        fix.shape = &shape;
        fix.filter.categoryBits = category;
        fix.filter.maskBits = mask;
        fix.isSensor = true;
        body->CreateFixture(&fix);
        return body;
    }

    b2Body* createStaticCircle(float x, float y, float radius, uint16 category, uint16 mask) {
        b2BodyDef def;
        def.type = b2_staticBody;
        def.position.Set(x / 100.0f, y / 100.0f);
        b2Body* body = world.CreateBody(&def);
        b2CircleShape shape;
        shape.m_radius = radius / 100.0f;
        b2FixtureDef fix;
        fix.shape = &shape;
        fix.filter.categoryBits = category;
        fix.filter.maskBits = mask;
        fix.isSensor = true;
        body->CreateFixture(&fix);
        return body;
    }

    b2Body* createStaticRect(float x, float y, float w, float h, uint16 category, uint16 mask) {
        b2BodyDef def;
        def.type = b2_staticBody;
        def.position.Set(x / 100.0f, y / 100.0f);
        b2Body* body = world.CreateBody(&def);
        b2PolygonShape shape;
        shape.SetAsBox(w / 2.0f / 100.0f, h / 2.0f / 100.0f);
        b2FixtureDef fix;
        fix.shape = &shape;
        fix.filter.categoryBits = category;
        fix.filter.maskBits = mask;
        fix.isSensor = true;
        body->CreateFixture(&fix);
        return body;
    }

    void step(float dt) {
        world.Step(dt, 1, 1);
    }

    void clear() {
        for (auto* b : bossBodies) world.DestroyBody(b);
        for (auto* b : pickupBodies) world.DestroyBody(b);
        if (workerBody) { world.DestroyBody(workerBody); workerBody = nullptr; }
        if (wallBody) { world.DestroyBody(wallBody); wallBody = nullptr; }
        bossBodies.clear();
        pickupBodies.clear();
    }
};

} // namespace bm