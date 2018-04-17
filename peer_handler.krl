ruleset peer_handler {
  meta {
    name "Peer Subscriptions Handler"
    description <<
Provides advanced functionality around subscriptions for peers
>>

    use module io.picolabs.subscription alias Subscriptions

    shares getPeerInfo, getPeers, getPeersWithId, findPeersWith, findWith, __testing
    provides getPeers, getPeersWithId, findPeersWith, findWith
  }

  global {
    __testing = {
      "queries": [
        { "name": "__testing" },
        { "name": "getPeerInfo" }
      ],
      "events": [
        { "domain": "peers", "type": "system_check_needed", "attrs": ["role"]}
      ]
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

    findPeersWith = function(role, field, matches) {
      getPeers(role).filter(function(peer) {
        matches == peer{[field]}
      })
    };

    findWith = function(field, matches) {
      peerInfo = getPeerInfo();
      Subscriptions:established()
        .filter(function(sub) {
          matches == sub{field}
        })
        .map(function(p) {
          // Merge the extra peer information with the subscription information
          id = peerInfo{[p{"Tx"}]} => peerInfo{[p{"Tx"}]}
                                    | "";

          p.put(["id"], id);
        });
    };
  }

  rule start_id_handshake {
    select when peers need_id
             or wrangler subscription_added
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
