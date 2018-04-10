// Basic ruleset to help quickly setup the project.

ruleset system_manager {
  meta {
    name "System Manager"
    description <<Fast Flower Delivery system startup manager>>

    shares __testing
  }

  global {
    __testing = {
      "queries": [],
      "events": [
        { "domain": "manager", "type": "new_shop", "attrs": ["name"] },
        { "domain": "manager", "type": "new_driver", "attrs": ["name"] }
      ]
    };
  }

  rule new_flower_shop {
    select when manager new_shop
    pre {
      name = event:attrs{"name"} => event:attrs{"name"}
                                 |  "Shop " + random:uuid();
    }
    fired {
      raise wrangler event "child_creation"
        attributes {
          "name": name,
          "color": "#4682B4",
          "rid": [
            "io.picolabs.logging",
            "io.picolabs.subscription"
            // Add addition shop rulsets here
          ]
        }
    }
  }

  rule new_driver {
    select when manager new_driver
    pre {
      name = event:attrs{"name"} => event:attrs{"name"}
                                 |  "Driver " + random:uuid();
    }
    fired {
      raise wrangler event "child_creation"
        attributes {
          "name": name,
          "color": "#500b75",
          "rid": [
            "io.picolabs.logging",
            "io.picolabs.subscription",
            "driver"
          ]
        }
    }
  }

  rule child_created {
    select when wrangler new_child_created
    send_directive("Child Created", {})
    fired {
      raise manager event "child_created"
    }
  }
}


