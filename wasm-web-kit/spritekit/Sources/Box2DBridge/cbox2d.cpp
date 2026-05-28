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
std::vector<b2Joint*> g_joints;
std::deque<ContactRec> g_contacts;
Listener g_listener;
}

extern "C" {

void cb_reset(float gx, float gy) {
    g_world = std::make_unique<b2World>(b2Vec2(gx, gy));
    g_bodies.clear();
    g_contacts.clear();
    g_joints.clear();
    g_listener.q = &g_contacts;
    g_world->SetContactListener(&g_listener);
}

static int addBody(float x, float y, int dynamic, b2Shape* shape, uint16_t cat, uint16_t mask, int sensor) {
    if (!g_world) cb_reset(0, 0);
    b2BodyDef bd;
    bd.type = dynamic ? b2_dynamicBody : b2_staticBody;
    bd.position.Set(x, y);
    bd.fixedRotation = false;
    int id = (int)g_bodies.size();
    bd.userData.pointer = (uintptr_t)id;
    b2Body* body = g_world->CreateBody(&bd);
    b2FixtureDef fd; fd.shape = shape; fd.density = 1.0f; fd.friction = 0.2f; fd.restitution = 0.1f;
    fd.isSensor = sensor != 0;
    fd.filter.categoryBits = cat; fd.filter.maskBits = mask;
    body->CreateFixture(&fd);
    g_bodies.push_back(body);
    return id;
}

int cb_add_box(float x, float y, float hw, float hh, int dynamic, uint16_t cat, uint16_t mask, int sensor) {
    b2PolygonShape s; s.SetAsBox(hw, hh);
    return addBody(x, y, dynamic, &s, cat, mask, sensor);
}
int cb_add_circle(float x, float y, float r, int dynamic, uint16_t cat, uint16_t mask, int sensor) {
    b2CircleShape s; s.m_radius = r;
    return addBody(x, y, dynamic, &s, cat, mask, sensor);
}
// Convex polygon body. Points are xy pairs in *body-local* coordinates
// (SpriteKit's polygonFrom: passes the path's points relative to the node's
// position). Box2D 2.4 enforces a max of 8 vertices and requires the polygon
// to be convex; we silently truncate larger inputs to the first 8 points.
int cb_add_polygon(float x, float y, const float* xy, int count, int dynamic,
                   uint16_t cat, uint16_t mask, int sensor) {
    if (count < 3) return cb_add_box(x, y, 1, 1, dynamic, cat, mask, sensor);
    int n = count > b2_maxPolygonVertices ? b2_maxPolygonVertices : count;
    b2Vec2 verts[b2_maxPolygonVertices];
    for (int i = 0; i < n; ++i) { verts[i].Set(xy[i*2], xy[i*2+1]); }
    b2PolygonShape s;
    s.Set(verts, n);
    return addBody(x, y, dynamic, &s, cat, mask, sensor);
}
// Single edge segment. Used by SKPhysicsBody(edgeFrom:to:).
int cb_add_edge(float x1, float y1, float x2, float y2, uint16_t cat, uint16_t mask) {
    if (!g_world) cb_reset(0, 0);
    b2BodyDef bd; bd.type = b2_staticBody; bd.position.Set(0, 0);
    int id = (int)g_bodies.size();
    bd.userData.pointer = (uintptr_t)id;
    b2Body* body = g_world->CreateBody(&bd);
    b2EdgeShape s; s.SetTwoSided(b2Vec2(x1, y1), b2Vec2(x2, y2));
    b2FixtureDef fd; fd.shape = &s; fd.density = 1.f; fd.friction = 0.2f;
    fd.filter.categoryBits = cat; fd.filter.maskBits = mask;
    body->CreateFixture(&fd);
    g_bodies.push_back(body);
    return id;
}
// Polyline (open chain) or closed loop of edges. Used by SKPhysicsBody(edgeLoopFrom:)
// and edgeChainFrom: for arbitrary CGPaths.
int cb_add_chain(const float* xy, int count, int closed, uint16_t cat, uint16_t mask) {
    if (!g_world) cb_reset(0, 0);
    if (count < 2) return -1;
    b2BodyDef bd; bd.type = b2_staticBody; bd.position.Set(0, 0);
    int id = (int)g_bodies.size();
    bd.userData.pointer = (uintptr_t)id;
    b2Body* body = g_world->CreateBody(&bd);
    std::vector<b2Vec2> verts(count);
    for (int i = 0; i < count; ++i) verts[i].Set(xy[i*2], xy[i*2+1]);
    b2ChainShape s;
    if (closed) s.CreateLoop(verts.data(), count);
    else        s.CreateChain(verts.data(), count, verts.front(), verts.back());
    b2FixtureDef fd; fd.shape = &s; fd.density = 1.f; fd.friction = 0.2f;
    fd.filter.categoryBits = cat; fd.filter.maskBits = mask;
    body->CreateFixture(&fd);
    g_bodies.push_back(body);
    return id;
}
// ----- Forces / torques (newly used by SKAction.applyForce/Torque + SKFieldNode)
void cb_apply_force(int b, float fx, float fy) {
    if (b >= 0 && b < (int)g_bodies.size())
        g_bodies[b]->ApplyForceToCenter(b2Vec2(fx, fy), true);
}
void cb_apply_impulse(int b, float ix, float iy) {
    if (b >= 0 && b < (int)g_bodies.size())
        g_bodies[b]->ApplyLinearImpulseToCenter(b2Vec2(ix, iy), true);
}
void cb_apply_torque(int b, float t) {
    if (b >= 0 && b < (int)g_bodies.size()) g_bodies[b]->ApplyTorque(t, true);
}
void cb_apply_angular_impulse(int b, float i) {
    if (b >= 0 && b < (int)g_bodies.size()) g_bodies[b]->ApplyAngularImpulse(i, true);
}
void cb_set_angular_velocity(int b, float w) {
    if (b >= 0 && b < (int)g_bodies.size()) g_bodies[b]->SetAngularVelocity(w);
}
float cb_get_angular_velocity(int b) {
    return (b >= 0 && b < (int)g_bodies.size()) ? g_bodies[b]->GetAngularVelocity() : 0.f;
}

// ----- Joints. id < 0 means failure; g_joints (declared above) owns b2Joint*.
static int storeJoint(b2Joint* j) {
    int id = (int)g_joints.size(); g_joints.push_back(j); return id;
}
int cb_add_joint_pin(int a, int b, float ax, float ay, int enableLimits,
                     float lower, float upper, float frictionTorque, float motorSpeed) {
    if (!g_world || a < 0 || b < 0 || a >= (int)g_bodies.size() || b >= (int)g_bodies.size()) return -1;
    b2RevoluteJointDef def;
    def.Initialize(g_bodies[a], g_bodies[b], b2Vec2(ax, ay));
    def.enableLimit = enableLimits != 0;
    def.lowerAngle  = lower; def.upperAngle = upper;
    def.maxMotorTorque = frictionTorque;
    def.motorSpeed = motorSpeed;
    def.enableMotor = motorSpeed != 0.f || frictionTorque != 0.f;
    return storeJoint(g_world->CreateJoint(&def));
}
int cb_add_joint_spring(int a, int b, float ax, float ay, float bx, float by,
                        float frequency, float damping) {
    if (!g_world || a < 0 || b < 0 || a >= (int)g_bodies.size() || b >= (int)g_bodies.size()) return -1;
    b2DistanceJointDef def;
    def.Initialize(g_bodies[a], g_bodies[b], b2Vec2(ax, ay), b2Vec2(bx, by));
    b2LinearStiffness(def.stiffness, def.damping, frequency, damping,
                      g_bodies[a], g_bodies[b]);
    return storeJoint(g_world->CreateJoint(&def));
}
int cb_add_joint_sliding(int a, int b, float ax, float ay, float dx, float dy,
                         int enableLimits, float lower, float upper) {
    if (!g_world || a < 0 || b < 0 || a >= (int)g_bodies.size() || b >= (int)g_bodies.size()) return -1;
    b2PrismaticJointDef def;
    def.Initialize(g_bodies[a], g_bodies[b], b2Vec2(ax, ay), b2Vec2(dx, dy));
    def.enableLimit = enableLimits != 0;
    def.lowerTranslation = lower; def.upperTranslation = upper;
    return storeJoint(g_world->CreateJoint(&def));
}
int cb_add_joint_limit(int a, int b, float ax, float ay, float bx, float by, float maxLength) {
    if (!g_world || a < 0 || b < 0 || a >= (int)g_bodies.size() || b >= (int)g_bodies.size()) return -1;
    b2DistanceJointDef def;
    def.Initialize(g_bodies[a], g_bodies[b], b2Vec2(ax, ay), b2Vec2(bx, by));
    def.length = 0; def.minLength = 0; def.maxLength = maxLength;
    return storeJoint(g_world->CreateJoint(&def));
}
int cb_add_joint_fixed(int a, int b, float ax, float ay) {
    if (!g_world || a < 0 || b < 0 || a >= (int)g_bodies.size() || b >= (int)g_bodies.size()) return -1;
    b2WeldJointDef def;
    def.Initialize(g_bodies[a], g_bodies[b], b2Vec2(ax, ay));
    return storeJoint(g_world->CreateJoint(&def));
}
int cb_add_joint_distance(int a, int b, float ax, float ay, float bx, float by) {
    if (!g_world || a < 0 || b < 0 || a >= (int)g_bodies.size() || b >= (int)g_bodies.size()) return -1;
    b2DistanceJointDef def;
    def.Initialize(g_bodies[a], g_bodies[b], b2Vec2(ax, ay), b2Vec2(bx, by));
    return storeJoint(g_world->CreateJoint(&def));
}
void cb_remove_joint(int id) {
    if (id < 0 || id >= (int)g_joints.size() || !g_joints[id]) return;
    g_world->DestroyJoint(g_joints[id]); g_joints[id] = nullptr;
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
