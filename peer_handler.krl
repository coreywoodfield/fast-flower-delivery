ruleset peer_handler {
  meta {
    name "Peer Subscriptions Handler"
    description <<
Provides advanced functionality around subscriptions for peers
>>

    use module io.picolabs.subscription alias Subscriptions
    use module io.picolabs.wrangler alias wrangler

    shares getAll, getPeerInfo, getPeers, getPeersWithId, findPeersWith, findWith, id, __testing
    provides getAll, getPeers, getPeersWithId, findPeersWith, findWith
  }

  global {
    __testing = {
      "queries": [
        { "name": "__testing" },
        { "name": "getAll" },
        { "name": "getPeerInfo" }
      ],
      "events": [
        { "domain": "peers", "type": "system_check_needed", "attrs": ["role"]}
      ]
    };

    findPeersWith = function(role, field, matches) {
      getAll()
        .filter(function(peer) {
          matches == peer{[field]} && role == peer{"Tx_role"}
        })
    };

    findWith = function(field, matches) {
      getAll()
        .filter(function(sub) {
          matches == sub{field}
        })
    };

    getAll = function() {
      peerInfo = getPeerInfo();
      Subscriptions:established()
        .map(function(p) {
          // Merge the extra peer information with the subscription information
          id = peerInfo{[p{"Tx"}]} => peerInfo{[p{"Tx"}]}
                                    | "";

          p.put(["id"], id);
        });
    };

    getPeers = function(role) {
      findWith("Tx_role", role)
    };

    getPeersWithId = function(role, id) {
      findPeersWith(role, "id", id)
    };

    getPeerInfo = function() {
      ent:peerInfo => ent:peerInfo
                    | {}
    };

    id = function() {
      meta:picoId
    }
  }

  rule store_id_to_Tx {
    select when wrangler pending_subscription_approval
    pre {
      eci = event:attrs{"Tx"}
      host = event:attrs{"Tx_host"}
      picoId = wrangler:skyQuery(eci, "peer_handler", "id", {}, host)
      haveId = picoId => true | false
    }
    if haveId then
      send_directive("Storing id", { "id": shopId, "attrs": event:attrs })
    fired {
      ent:peerInfo := getPeerInfo().put([eci], id);
      raise peer event "id_stored"
        attributes { "tx": eci, "id": id }
    }
  }

  rule start_id_handshake {
    select when peers need_id
    pre {
      tx = event:attrs{"Tx"} => event:attrs{"Tx"}
                              | event:attrs{"_Tx"}
      host = event:attrs{"Tx_host"} => event:attrs{"Tx_host"}
                                     | meta:host

      e = {
        "eci": tx,
        "eid": meta:picoId,
        "domain": "peers",
        "type": "handshake",
        "attrs": {
          "picoId": meta:picoId,
          "host": host
        }
      }
    }
    event:send(e, host=host)
    fired {
      raise peers event "handshake_started" attributes e
    }
  }

  rule recieve_handshake {
    select when peers handshake where event:attrs{"picoId"}
    pre {
      // Find the peer doing the handshake
      matches = findWith("Rx", meta:eci)
      found = matches.length() == 1
      peer = found => matches.head()
                    | {}

      id = event:attrs{"picoId"}
    }
    if found then
      send_directive("Peer found", { "peer": peer, "id": id })
    fired {
      ent:peerInfo := getPeerInfo().put([peer{"Tx"}], id);
      raise peers event "handshake_completed" attributes { "peer": peer, "id": id }
    }
  }

  rule system_check {
    select when peers system_check_needed where event:attrs{"role"}
    pre {
      peers = getPeers(event:attrs{"role"})
      needIds = peers.filter(function(peer) {
        "" == peer{"id"}
      })

      idsNeeded = needIds.length() > 0
    }
    if idsNeeded then
      send_directive("System check getting missing ids", { "need_ids": needIds })
    fired {
      raise peers event "need_ids" attributes { "needIds": needIds }
    }
  }

  rule get_needed_ids {
    select when peers need_ids where event:attrs{"needIds"}
    foreach event:attrs{"needIds"} setting(needsId)
      pre {
        host = needsId{"Tx_host"} => needsId{"Tx_host"}
                                   | meta:host
        e = {
          "eci": needsId{"Tx"},
          "eid": meta:picoId,
          "domain": "peers",
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
        raise peers event "id_requests_sent" attributes event:attrs on final
      }
    // End foreach
  }
}
