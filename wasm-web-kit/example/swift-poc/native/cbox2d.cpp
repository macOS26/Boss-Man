// Tiny C shim around Box2D (C++), so Swift can drive a physics world via C interop.
#include <box2d/box2d.h>
extern "C" {
static b2World* g_world = nullptr;
static b2Body*  g_box   = nullptr;
void cb_init(void) {
    static b2World world(b2Vec2(0.0f, -10.0f));
    g_world = &world;
    b2BodyDef bd; bd.type = b2_dynamicBody; bd.position.Set(0.0f, 18.0f);
    g_box = world.CreateBody(&bd);
    b2PolygonShape box; box.SetAsBox(1.0f, 1.0f);
    g_box->CreateFixture(&box, 1.0f);
    b2BodyDef gd; gd.position.Set(0.0f, 0.0f);
    b2Body* ground = world.CreateBody(&gd);
    b2PolygonShape gb; gb.SetAsBox(60.0f, 1.0f);
    ground->CreateFixture(&gb, 0.0f);
}
void  cb_step(float dt) { if (g_world) g_world->Step(dt, 8, 3); }
float cb_box_y(void)    { return g_box ? g_box->GetPosition().y : -1.0f; }
}
