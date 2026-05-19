// MongoDB init script for UniFi Network Application
// Runs once when the MongoDB container first initializes.
// Templated by Ansible — passwords come from /opt/unifi/.env.
// Do not edit directly; re-run `make unifi` to regenerate.

db.getSiblingDB("unifi").createUser({
  user: "UNIFI_MONGO_USER_PLACEHOLDER",
  pwd: "UNIFI_MONGO_PASS_PLACEHOLDER",
  roles: [{ role: "dbOwner", db: "unifi" }]
});

db.getSiblingDB("unifi_stat").createUser({
  user: "UNIFI_MONGO_USER_PLACEHOLDER",
  pwd: "UNIFI_MONGO_PASS_PLACEHOLDER",
  roles: [{ role: "dbOwner", db: "unifi_stat" }]
});
