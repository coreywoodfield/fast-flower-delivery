ruleset gossip_node {
  meta {
    name "Gossip Node"
    description <<
Gossip Protocol for Drivers
>>
    author "Curtis Oakley"

    use module io.picolabs.subscription alias Subscriptions

    shares frequency, getPeer, getPeers, getPeerInfo, getSeen, getMessages, processing, updateSeen, __testing
    provides getMessages
  }

  global {
    __testing = {
      "queries": [
        { "name": "__testing" },
        { "name": "frequency" },
        { "name": "getPeer" },
        { "name": "getPeers" },
        { "name": "getPeerInfo" },
        { "name": "getSeen" },
        { "name": "getMessages" },
        { "name": "processing" }
      ],
      "events": [
        { "domain": "gossip", "type": "heartbeat", "attrs": [] },
        { "domain": "gossip", "type": "process", "attrs": ["status"] },
        { "domain": "gossip", "type": "interval", "attrs": ["interval"] },
        { "domain": "explicit", "type": "system_check_needed", "attrs": []}
      ]
    };

    frequency = function() {
      ent:frequency
    };

    findPeersWith = function(field, matches) {
      getPeers().filter(function(peer) {
        matches == peer{[field]}
      })
    };

    // Gets a list of rumors that are needed based on the provided seen message
    getNeededRumors = function(seen) {
      getRumors()
        .filter(function(rumor) {
          // Rumors are needed if the sequence number we have is greater than their seen sequence number,
          // or if they haven't even seen this origin.
          (seen >< rumor{"OriginId"}) =>
            seen{[rumor{"OriginId"}]} < rumor{"SequenceNum"} |
            true
        })
        .values()
    };

    getPeer = function() {
      // Randomly select a peer, but give peers that are futher behind in sequence a greater chance.
      peers = getPeers();

      // Hold a lottery
      // Peers that haven't seen as many temperatures as this pico get more entries into the lottery
      lottery = peers.map(function(peer) {
        behind = getNeededRumors(peer{"seen"}).length();
        numTickets = behind > 0 => behind * 2
                                 | 1;
        {
          "numTickets": numTickets,
          "peer": peer
        };
      });
      lottery = lottery.map(function(lot, i) {
        // This is very ineffecient O(2^n), but I couldn't figure out another way to do this in KRL
        {
          "lotteryMax": lottery.slice(0, i).reduce(function(c, lot2) { c + lot2{"numTickets"} }, 0),
          "numTickets": lot{"numTickets"},
          "peer": lot{"peer"}
        };
      });
      lotteryMin = lottery.head(){"numTickets"};
      lotteryMax = lottery[lottery.length() - 1]{"lotteryMax"};

      winner = random:integer(lotteryMax, lotteryMin);

      winnersList = lottery.filter(function(lotteryPeer) {
        lotteryPeer{"lotteryMax"} <= winner;
      });
      winnersList[winnersList.length() - 1]{"peer"};
    };

    getPeers = function() {
      peerInfo = getPeerInfo();
      Subscriptions:established()
        .filter(function(sub) {
          // Remove any non-driver subscriptions
          sub{"Tx_role"} == "driver"
        })
        .map(function(p) {
          // Merge the extra peer information with the subscription information
          id = peerInfo{[p{"Tx"}, "id"]} => peerInfo{[p{"Tx"}, "id"]}
                                          | "";
          seen = peerInfo{[p{"Tx"}, "seen"]} => peerInfo{[p{"Tx"}, "seen"]}
                                              | {};

          p.put(["id"], id).put(["seen"], seen);
        });
    };

    getPeerPeers = function(peer) {
      host = peer{"Tx_host"} => peer{"Tx_host"}
                              | meta:host;
      eci = peer{"Tx"};

      url = host + "/sky/cloud/" + eci + "/" + meta:rid + "/getPeers";
      response = http:get(url);
      (response{"status_code"} == 200) => response{"content"}.decode()
                                        | null
    };

    getPeerInfo = function() {
      ent:peerInfo => ent:peerInfo
                    | {}
    };

    getRandomRumorMessageFor = function(peer) {
      seen = (peer >< "seen") => peer{"seen"} | {};
      neededRumors = getNeededRumors(seen);
      neededRumors[random:integer(neededRumors.length() - 1)];
    }

    getRumors = function() {
      ent:rumors => ent:rumors
                  | {};
    }

    getSeen = function() {
      ent:seen => ent:seen
                | {};
    };

    getMessages = function() {
      getRumors().values();
    };

    prepareMessage = function(subscriber) {
      msgType = (random:integer(1) == 0) => "rumor"
                                          | "seen";
      attrs = (msgType == "rumor") => getRandomRumorMessageFor(subscriber)
                                    | getSeen();
      subscriber => {
        "eci": subscriber{"Tx"},
        "eid": meta:picoId + "_" + msgType,
        "domain": "gossip",
        "type": msgType,
        "attrs": attrs
      } | null;
    };

    processing = function() {
      ent:processing
    };

    updateSeen = function(originId) {
      seen = getSeen();
      maxCompleteSequenceNum = getRumors()
        .filter(function(msg, id) {
          msg{"OriginId"} == originId
        })
        .values()
        .sort(function(a, b) {
          (a{"SequenceNum"} <  b{"SequenceNum"}) => -1 |
          (a{"SequenceNum"} == b{"SequenceNum"}) =>  0 |
                                                     1
        })
        .reduce(function(current, msg) {
          (current == msg{"SequenceNum"}) => current + 1
                                           | current
        }, 0);
      maxForSeen = (maxCompleteSequenceNum > 0) => maxCompleteSequenceNum - 1
                                                 | 0;

      originId => seen.put([originId], maxForSeen)
                | seen;
    };
  }


  // Initialize when this ruleset is added
  rule initialize {
    select when wrangler ruleset_added where rid == meta:rid
    // Start the gossip heartbeat event (sending this way so I can set the eid)
    event:send({
      "eci": meta:eci,
      "eid": "heartbeat",
      "domain": "gossip",
      "type": "heartbeat",
      "attrs": {}
    })
    fired {
      ent:processing := "on";
      ent:frequency := 5;
      raise gossip event "initialized" attributes event:attrs
    }
  }


  // -------------------------
  // Subscriptions
  // -------------------------

  rule auto_accept_subscription {
    select when wrangler inbound_pending_subscription_added Rx_role re#^driver$#
    pre {
      attributes = event:attrs.klog("Subscription:")
    }
    fired {
      raise wrangler event "pending_subscription_approval" attributes attributes
    }
  }

  rule start_id_handshake {
    select when wrangler subscription_added Rx_role re#^driver$#
         or wrangler subscription_added status re#^outbound$#
         or gossip need_id where event:attrs{"Tx"}
    pre {
      tx = event:attrs{"Tx"} => event:attrs{"Tx"}
                              | event:attrs{"_Tx"}
      host = event:attrs{"Tx_host"} => event:attrs{"Tx_host"}
                                     | meta:host

      e = {
        "eci": tx,
        "eid": meta:picoId,
        "domain": "gossip",
        "type": "handshake",
        "attrs": {
          "picoId": meta:picoId,
          "host": host
        }
      }
    }
    event:send(e, host=host)
    fired {
      raise gossip event "handshake_started" attributes e
    }
  }

  rule recieve_handshake {
    select when gossip handshake where event:attrs{"picoId"}
    pre {
      // Find the peer doing the handshake
      matches = findPeersWith("Rx", meta:eci)
      found = matches.length() == 1
      peer = found => matches.head()
                    | {}

      id = event:attrs{"picoId"}
    }
    if found then
      send_directive("Peer found", { "peer": peer, "id": id })
    fired {
      ent:peerInfo := getPeerInfo().put([peer{"Tx"}, "id"], id);
      raise gossip event "handshake_completed" attributes { "peer": peer, "id": id }
    }
  }

  rule system_check {
    select when explicit system_check_needed
    pre {
      peers = getPeers()
      needIds = peers.filter(function(peer) {
        "" == peer{"id"}
      })

      idsNeeded = needIds.length() > 0
      needMorePeers = peers.length() == 1

      performFix = idsNeeded || needMorePeers
    }
    if performFix then
      send_directive("System check performing fixes", { "need_ids": needIds, "need_more_peers": needMorePeers })
    fired {
      raise explicit event "need_ids" attributes { "needIds": needIds } if idsNeeded;
      raise explicit event "need_more_peers" if needMorePeers
    }
  }

  rule get_needed_ids {
    select when explicit need_ids where event:attrs{"needIds"}
    foreach event:attrs{"needIds"} setting(needsId)
      pre {
        host = needsId{"Tx_host"} => needsId{"Tx_host"}
                                   | meta:host
        e = {
          "eci": needsId{"Tx"},
          "eid": meta:picoId,
          "domain": "gossip",
          "type": "need_id",
          "attrs": {
            "picoId": meta:picoId,
            "Tx": needsId{"Rx"},
            "Tx_host": meta:host
          }
        }
      }
      event:send(e, host=host)
      always {
        raise explicit event "id_requests_sent" attributes event:attrs on final
      }
    // End foreach
  }

  // Randomly selects a new peer and attempts to connect with them
  rule connect_to_more_peers {
    select when explicit need_more_peers
    pre {
      firstPeer = getPeers()[0]
      peersPeers = getPeerPeers(firstPeer)
      possiblePeers = peersPeers.filter(function(peer) {
        peer{"id"} != "" && peer{"id"} != meta:picoId
      })
      havePeers = possiblePeers.length() > 0

      connectTo = havePeers => possiblePeers[random:integer(possiblePeers.length() - 1)]
                             | {}

      tx_host = connectTo{"Tx_host"} => connectTo{"Tx_host"}
                                      | meta:host

      subscriptionInfo = {
        "name": meta:picoId + " <-> " + connectTo{"id"},
        "Rx_role": "driver",
        "Tx_role": "driver",
        "Tx_host": tx_host,
        "channel_type": "subscription",
        "wellKnown_Tx": connectTo{"Tx"}
      }
    }
    if havePeers then
      send_directive("Connecting to new peer", { "subscription": subscriptionInfo })
    fired {
      raise wrangler event "subscription" attributes subscriptionInfo
    }
  }


  // -------------------------
  // Gossiping
  // -------------------------

  rule gossip_heartbeat {
    select when gossip heartbeat
    pre {
      subscriber = getPeer()
      msg = prepareMessage(subscriber).klog("Heartbeat Message:")
    }
    if msg then
      event:send(msg, host=subscriber{"Tx_host"})
    always {
      // Schedule to run again in n seconds
      schedule gossip event "heartbeat" at time:add(time:now(), { "seconds": ent:frequency })
    }
  }

  // Receive and store a rumor about temperature
  rule gossip_rumor {
    // Only run when processing flag is true (except for internally generated explicit rumor events)
    select when gossip rumor where ent:processing == "on" && event:attrs{"MessageId"}
         or explicit rumor
    pre {
      msgId = event:attrs{"MessageId"}

      // Get the origin and sequence number of this rumor
      idParts = msgId.split(re#:#)
      originId = idParts[0]
      sequenceNum = idParts[1].as("Number")

      msg = event:attrs
          .put(["SequenceNum"], sequenceNum)
          .put(["OriginId"], originId)

      rumors = getRumors()

      seen = rumors >< msgId
    }
    if not seen then
      send_directive("Received rumor", msg)
    fired {
      ent:rumors := rumors.put([msgId], msg);
      ent:seen := updateSeen(originId);

      raise gossip event "rumor_seen" attributes msg
    }
  }

  // Handles a seen message event
  // Figures out rumors that the sender hasn't seen and sends those rumors to them
  rule gossip_seen {
    select when gossip seen where ent:processing == "on"
    pre {
      // Find who sent us a seen message
      matches = findPeersWith("Rx", meta:eci)
      found = matches.length() == 1
      peer = found => matches.head()
                    | {}

      // Figure out what rumors we need to send
      peerSeen = event:attrs.map(function(sequenceNum) {
        sequenceNum.as("Number")
      })
      rumorsToSend = getNeededRumors(peerSeen)
    }
    if found then
      send_directive("Sending missing messages", { "missingRumors": rumorsToSend })
    fired {
      ent:peerInfo := getPeerInfo().put([peer{"Tx"}, "seen"], peerSeen);
      raise gossip event "need_rumors"
        attributes {
          "peer": peer,
          "rumorsNeeded": rumorsToSend
        }
    }
  }

  // This rule currently just triggers another rule to kick of some system checks
  rule rumor_seen {
    select when gossip rumor_seen
    always {
      raise explicit event "system_check_needed"
    }
  }

  // Sends every provided rumor to a peer
  rule transmit_rumors {
    select when gossip need_rumors
    foreach event:attrs{"rumorsNeeded"} setting(rumor)
      pre {
        peer = event:attrs{"peer"}

        host = peer{"Tx_host"} => peer{"Tx_host"}
                                | meta:host
      }
      event:send({
        "eci": peer{"Tx"},
        "eid": meta:picoId + "_rumor",
        "domain": "gossip",
        "type": "rumor",
        "attrs": rumor
      }, host=host)
      always {
        raise gossip event "rumors_transmitted" attributes event:attrs on final
      }
    // End foreach
  }

  // Set the gossip interval frequency
  rule gossip_interval {
    select when gossip interval
    pre {
      interval = event:attrs{"interval"}.as("Number")
    }
    if interval > 0 then
      send_directive("Frequency interval updated", { "interval": interval })
    fired {
      ent:frequency := interval;
      raise gossip event "interval_updated" attributes { "interval": interval }
    }
  }

  // Toggle gossip processing on or off
  rule gossip_process_on {
    select when gossip process status re#^on$#
    send_directive("Updated process status", { "status": "on" })
    fired {
      ent:processing := "on"
    }
  }
  rule gossip_process_off {
    select when gossip process status re#^off$#
    send_directive("Updated process status", { "status": "off" })
    fired {
      ent:processing := "off"
    }
  }
}
