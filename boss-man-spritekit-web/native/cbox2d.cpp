// Box2D shim for the SpriteKit-on-web physics layer. Exposes a flat C API the
// Swift SKPhysics layer calls. Coordinates are SpriteKit points treated as
// Box2D meters (the games use physics mainly for contact detection + velocity).
#include <box2d/box2d.h>
#include <vector>
#include <deque>
#include <memory>

namespace {
struct ContactRec { int catA, catB, bodyA, bodyB; };

struct Listener : b2ContactListener {
    std::deque<ContactRec>* q;
    void BeginContact(b2Contact* c) override {
        auto fa = c->GetFixtureA(); auto fb = c->GetFixtureB();
        q->push_back({ (int)fa->GetFilterData().categoryBits, (int)fb->GetFilterData().categoryBits,
                       (int)fa->GetBody()->GetUserData().pointer, (int)fb->GetBody()->GetUserData().pointer });
    }
};

std::unique_ptr<b2World> g_world;
std::vector<b2Body*> g_bodies;
std::deque<ContactRec> g_contacts;
Listener g_listener;
}

extern "C" {

void cb_reset(float gx, float gy) {
    g_world = std::make_unique<b2World>(b2Vec2(gx, gy));
    g_bodies.clear();
    g_contacts.clear();
    g_listener.q = &g_contacts;
    g_world->SetContactListener(&g_listener);
}

static int addBody(float x, float y, int dynamic, b2Shape* shape, uint16_t cat, uint16_t mask) {
    if (!g_world) cb_reset(0, 0);
    b2BodyDef bd;
    bd.type = dynamic ? b2_dynamicBody : b2_staticBody;
    bd.position.Set(x, y);
    bd.fixedRotation = false;
    int id = (int)g_bodies.size();
    bd.userData.pointer = (uintptr_t)id;
    b2Body* body = g_world->CreateBody(&bd);
    b2FixtureDef fd; fd.shape = shape; fd.density = 1.0f; fd.friction = 0.2f; fd.restitution = 0.1f;
    fd.isSensor = false;
    fd.filter.categoryBits = cat; fd.filter.maskBits = mask;
    body->CreateFixture(&fd);
    g_bodies.push_back(body);
    return id;
}

int cb_add_box(float x, float y, float hw, float hh, int dynamic, uint16_t cat, uint16_t mask) {
    b2PolygonShape s; s.SetAsBox(hw, hh);
    return addBody(x, y, dynamic, &s, cat, mask);
}
int cb_add_circle(float x, float y, float r, int dynamic, uint16_t cat, uint16_t mask) {
    b2CircleShape s; s.m_radius = r;
    return addBody(x, y, dynamic, &s, cat, mask);
}
void cb_set_velocity(int b, float vx, float vy) { if (b >= 0 && b < (int)g_bodies.size()) g_bodies[b]->SetLinearVelocity(b2Vec2(vx, vy)); }
void cb_set_transform(int b, float x, float y, float angle) { if (b >= 0 && b < (int)g_bodies.size()) g_bodies[b]->SetTransform(b2Vec2(x, y), angle); }
void cb_get_position(int b, float* x, float* y) { if (b >= 0 && b < (int)g_bodies.size()) { auto p = g_bodies[b]->GetPosition(); *x = p.x; *y = p.y; } }
float cb_get_angle(int b) { return (b >= 0 && b < (int)g_bodies.size()) ? g_bodies[b]->GetAngle() : 0.f; }
void cb_step(float dt) { if (g_world) g_world->Step(dt, 8, 3); }
int cb_poll_contact(int* catA, int* catB, int* bodyA, int* bodyB) {
    if (g_contacts.empty()) return 0;
    auto c = g_contacts.front(); g_contacts.pop_front();
    *catA = c.catA; *catB = c.catB; *bodyA = c.bodyA; *bodyB = c.bodyB;
    return 1;
}
}
