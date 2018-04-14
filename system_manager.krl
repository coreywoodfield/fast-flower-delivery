// Basic ruleset to help quickly setup the project.

ruleset system_manager {
  meta {
    name "System Manager"
    description <<Fast Flower Delivery system startup manager>>

    use module io.picolabs.wrangler alias wrangler

    shares getDriver, __testing
  }

  global {
    __testing = {
      "queries": [
        { "name": "getDriver" }
      ],
      "events": [
        { "domain": "manager", "type": "new_shop", "attrs": ["name", "logging_on"] },
        { "domain": "manager", "type": "new_driver", "attrs": ["name", "logging_on"] },
        { "domain": "manager", "type": "introduce_nodes", "attrs": ["rx_eci", "tx_eci", "name", "rx_role", "tx_role", "tx_host", "rx_host"] },
        { "domain": "manager", "type": "unneeded_child", "attrs": ["name"] },
        { "domain": "manager", "type": "need_reset", "attrs": ["confirmation"] }
      ]
    };

    flowerShopRules = [
      "io.picolabs.logging",
      "io.picolabs.subscription",
      "flower_shop"
      // Add addition shop rulesets here
    ];

    driverRules = [
      "io.picolabs.logging",
      "io.picolabs.subscription",
      "gossip_node",
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

    getDriver = function(notWithThisId) {
      driversById = ent:drivers => ent:drivers
                                 | {};

      drivers = children()
        .filter(function(child) {
          driversById >< child{"id"}
        })
        .filter(function(d) {
          d{"id"} != notWithThisId
        });

      driver = drivers.length() > 0 => drivers[random:integer(drivers.length() - 1)]
                                     | null;
      driver
    }
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

  rule driver_created {
    select when wrangler new_child_created where event:attrs{["rs_attrs", "node_type"]} == "driver"
    pre {
      id = event:attrs{"id"}
      name = event:attrs{"name"}
    }
    always {
      ent:drivers := ent:drivers.defaultsTo({}).put(id, name);
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

  // Introduces the newly created child to a driver
  rule create_subscriptions {
    // Select this rule after the rulesets have been installed, and the setup events (if any) have been sent
    select when manager rulesets_installed where event:attrs{["rs_attrs", "node_setup", "events"]}.length() == 0
             or manager child_initialized
    pre {
      driver = getDriver(event:attrs{"id"})

      name = driver => driver{"name"} + " <-> " + event:attrs{"name"}
                     | ""
      role = (driver && event:attrs{["rs_attrs", "node_type"]} == "shop") => "shop"
                                                                           | "driver"
    }
    if driver then
        send_directive("Creating subscription", { "name": name, "role": role, "driver": driver })
    fired {
      raise manager event "introduce_nodes"
        attributes {
          "rx_eci": event:attrs{"eci"},
          "rx_role": role,
          "tx_eci": driver{"eci"},
          "tx_role": "driver",
          "name": name
        }
    }
  }

  // Introduces on node to another node
  rule introduce_nodes {
        select when manager introduce_nodes
                    where event:attrs{"rx_eci"} && event:attrs{"tx_eci"} && event:attrs{"name"}
        pre {
            tx_host = event:attrs{"tx_host"} => event:attrs{"tx_host"}
                                              | meta:host
            rx_host = event:attrs{"rx_host"} => event:attrs{"rx_host"}
                                              | meta:host

            tx_role = event:attrs{"tx_role"} => event:attrs{"tx_role"}
                                              | "node"
            rx_role = event:attrs{"rx_role"} => event:attrs{"rx_role"}
                                              | "node"

            name = event:attrs{"name"}
            toEci = event:attrs{"rx_eci"}
            wellKnownEci = event:attrs{"tx_eci"}

            subscriptionInfo = {
                "name": name,
                "Rx_role": rx_role,
                "Tx_role": tx_role,
                "Tx_host": tx_host,
                "channel_type": "subscription",
                "wellKnown_Tx": wellKnownEci
            }

            event = {
                "eci": toEci,
                "eid": "sm_introduce",
                "domain": "wrangler",
                "type": "subscription",
                "attrs": subscriptionInfo
            }
        }
        every {
            send_directive("Introducing nodes", { "introduce": toEci, "to": wellKnownEci, "roles": [rx_role, tx_role] })
            event:send(event, host=rx_host)
        }
        fired {
            raise manager event "node_introduced" attributes event
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


