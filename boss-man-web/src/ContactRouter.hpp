#pragma once
#include <functional>
#include <box2d/box2d.h>
#include "PhysicsCategories.hpp"

namespace bm {

struct CollisionPair {
    uint16 catA, catB;
    b2Body* bodyA, * bodyB;
};

class ContactRouter : public b2ContactListener {
public:
    std::vector<CollisionPair> contacts;

    void BeginContact(b2Contact* contact) override {
        b2Fixture* fA = contact->GetFixtureA();
        b2Fixture* fB = contact->GetFixtureB();
        uint16 catA = fA->GetFilterData().categoryBits;
        uint16 catB = fB->GetFilterData().categoryBits;
        b2Body* bA = fA->GetBody();
        b2Body* bB = fB->GetBody();
        contacts.push_back({catA, catB, bA, bB});
        contacts.push_back({catB, catA, bB, bA});
    }

    void clear() { contacts.clear(); }
};

} // namespace bm