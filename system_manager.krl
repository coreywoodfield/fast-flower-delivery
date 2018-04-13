// Basic ruleset to help quickly setup the project.

ruleset system_manager {
  meta {
    name "System Manager"
    description <<Fast Flower Delivery system startup manager>>
    
    use module io.picolabs.wrangler alias wrangler

    shares __testing
  }

  global {
    __testing = {
      "queries": [],
      "events": [
        { "domain": "manager", "type": "new_shop", "attrs": ["name", "logging_on"] },
        { "domain": "manager", "type": "new_driver", "attrs": ["name", "logging_on"] },
        { "domain": "manager", "type": "unneeded_child", "attrs": ["name"] },
        { "domain": "manager", "type": "need_reset", "attrs": ["confirmation"] }
      ]
    };
    
    flowerShopRules = [
      "io.picolabs.logging",
      "io.picolabs.subscription"
      // Add addition shop rulesets here
    ];
    
    driverRules = [
      "io.picolabs.logging",
      "io.picolabs.subscription",
      "driver"
      // Add additional driver rulesets here
    ];
    
    children = function() {
      wrangler:children()
    };
    
    findChildrenByName = function(name) {
      children().filter(function(child) {
        child{"name"} == name
      })
    };
  }


  // -------------------------
  // Create Children
  // -------------------------
  
  rule new_flower_shop {
    select when manager new_shop
    pre {
      name = event:attrs{"name"} => event:attrs{"name"}
                                 |  "Shop " + random:uuid();
    }
    fired {
      raise manager event "new_child_pico"
        attributes {
          "name": name,
          "color": "#4682B4",
          "rulesets": flowerShopRules,
          "logging_on": event:attrs{"logging_on"},
          "type": "shop"
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
      raise manager event "new_child_pico"
        attributes {
          "name": name,
          "color": "#500b75",
          "rulesets": driverRules,
          "logging_on": event:attrs{"logging_on"},
          "type": "driver"
        }
    }
  }
  
  rule new_child {
    select when manager new_child_pico
    pre {
      logging_on = event:attrs{"logging_on"} => true | false;
      name = event:attrs{"name"}
      type = event:attrs{"type"}
      color = event:attrs{"color"}
      rules = event:attrs{"rulesets"}
                                 
      setup_events = logging_on => [{
                                      "domain": "picolog",
                                      "type": "begin",
                                      "attrs": {}
                                   }] 
                                 | []
    }
    fired {
      raise wrangler event "child_creation"
        attributes {
          "name": name,
          "color": color,
          "node_type": type,
          "node_setup": {
            "rulesets": rules,
            "events": setup_events
          }
        }
    }
  }


  // -------------------------
  // Initialize Children
  // -------------------------
  
  rule child_created {
    select when wrangler new_child_created
    send_directive("Child Created", event:attrs)
    fired {
      raise manager event "child_created" attributes event:attrs
    }
  }

  // Install all the needed rulsets into the child
  rule install_rulesets {
    select when wrangler child_initialized
    foreach event:attrs{["rs_attrs", "node_setup", "rulesets"]} setting(rule)
      // Installing using an event so the wrangler ruleset_added event is fired
      event:send({
        "eci": event:attrs{"eci"},
        "eid": "sm_install_ruleset",
        "domain": "wrangler",
        "type": "install_rulesets_requested",
        "attrs": {
          "rid": rule
        }
      })
      fired {
        raise manager event "rulesets_installed" attributes event:attrs on final
      }
    // End foreach
  }

  // Fire any addition events that the child needs for initialization
  rule initialize_child {
    select when manager rulesets_installed
    foreach event:attrs{["rs_attrs", "node_setup", "events"]} setting(eventInfo)
      event:send({
        "eci": event:attrs{"eci"},
        "eid": "sm_initialize",
        "domain": eventInfo{"domain"},
        "type": eventInfo{"type"},
        "attrs": eventInfo{"attrs"}
      })
      fired {
        raise manager event "child_initialized" attributes event:attrs on final
      }
    // End foreach
  }
  
  // Introduces the newly created child to another child
  rule create_subscriptions {
    // Select this rule after the rulesets have been installed, and the setup events (if any) have been sent
    select when manager rulesets_installed where event:attrs{["rs_attrs", "node_setup", "events"]}.length() == 0
             or manager child_initialized
    pre {
      a = event:attrs.klog("Attributes:")
      // TODO connect this node to an existing driver
    }
    send_directive("TODO", {})
    fired {
      raise manager event "connected_to_driver"
    }
  }
    


  // -------------------------
  // Remove Children
  // -------------------------
  
  // Removes the child node with the given name
  rule unneeded_child {
    select when manager unneeded_child where event:attrs{"name"}
    pre {
      name = event:attrs{"name"};
      matches = findChildrenByName(name);
      exists = matches.length() > 0;
      child = exists => matches.head().klog("CHILD")
                      | {}
      index = exists => children().index(child)
                      | -1
    }
    if exists then
      send_directive("Child deleted", { "child": child })
    fired {
      raise wrangler event "child_deletion"
        attributes {
          "id": child{"id"},
          "eci": child{"eci"}
        }
    }
  }
  
  // Removes all children
  rule remove_all_children {
    select when manager need_reset confirmation re#^confirm$#
    foreach children() setting(child)
      always {
        raise manager event "unneeded_child"
          attributes {
            "name": child{"name"}
          }
      }
    // End foreach
  }
}


