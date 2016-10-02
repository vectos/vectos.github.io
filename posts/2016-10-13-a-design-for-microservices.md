---
title: "A technical design: asynchronous and autonomous microservices with CQRS and Event Sourcing"
intro: "In this article I'll explain what is needed to implement a microservice with CQRS and Event Sourcing."
author: "mark"
---

In this article I'll explain what is needed to implement a microservice with CQRS and Event Sourcing [ref article...] by using Kafka, Cassandra, Akka and Scala.

Microservices is the buzzword in software development. What is it about? It's about creating a service which covers one thing very well. Lot's of IT departments love this idea for various reasons (you can split up teams, deployment, etc) and it is a great idea, but implementing such a thing can be very hard.

Why will it become hard? You'll be living distributed land and maybe you have to deal with network partitions, versioning, consensus, etc. As well you need to setup proper logging, deployment pipelines, etc. And one other thing: If you are using a strongly typed language, your types are useful for verification that your system works (compiling), but if put in production you cannot be sure what version of a protocol is used. In other words, does the format of your protocol line up with other services and how do you deal with these different versions?

## CQRS / Event Sourcing

== Explain what CQRS/Event Sourcing is ==

Properties of CQRS / Event sourcing:

- Seperation of concerns
- Keep all the information
- High performance
- Asynchronous communication

## Properties of a microservice

- Seperation of concerns - Each microservice is dealing with a specific bounded context. For example in a shop this could be separated in services which deal with products, orders, analytics, machine learning, etc
- Autonomous operation - It should not depend on other microservices or external dependencies. We don't want to create a monolith.
- Asynchronous communication - Communication should be asynchronous via message passing (by using pub/sub system like Kafka). A bad practice would be to use a RPC system which calls an external service. What if the network goes down? What if the protocol has changed (new version), what if it doesn't respond fast, etc..


## The design
So how do we marry these concepts? And what are the challenges I see at the moment?

### Challenges

- Event versioning and serialization format - The events which are distributed across the service should be versioned. The specification can change over time, so events can change aswell. Rewriting a microservice in a different language should not cause issues. This will happen over time, so take careful decisions about serializing your events and how to deal with them.
- Local or a global database - Sometimes it is oke to consume a Kafka topic and build up a local key value store or work with a embedded sql database. If it's not much data which will be read, it can boost performance and make the operational complexity a little easier. But if it's too much data, you should consider letting one service consume the topic and write it to a global database which will be used by other microservices to offer read models.
- Transactional and eventual Consistency - Transactional consistency is only needed when we working with the aggregate state. You need to make sure multiple events are persisted atomically. It's in most cases oke to have the read side eventual consistent.


### Write side

We'll use akka-persistence and akka-cluster-sharding to manage aggregates. Aggregates are as you know entities with a async boundary. Therefore it's needed to have a concurrency mechanism (Akka) in place to be sure that only one instance of a specific per aggregrate (partitioned by aggregate id) is created.

The commands are sharded by aggregate id and sent (via cluster sharding) to the specific aggregate. The specific aggregate is reconsistuted by akka-persistence by reading a optional available snapshot and events from the journal (Cassandra/JDBC database). When a command is valid, the events which are produced by this aggregate are persisted by akka-persistence.

This is where the serialization thing comes in. You can define custom serializers in Akka, which is recommended (otherwise you'll use the default Java serialization). I've used stamina in this case. It serializes the event as JSON plus it's version. The application code will contain evolution logic which allows you to modify the JSON AST so it works with the latest version. For example we could have added a extra field in the version which is a list. Adding a evolution for that case would be probably simple. Just initialize the property with a empty list.

The events are persisted to the Cassandra/JDBC database. We can also persist them to Kafka at once, but there is a problem with that.

While persisting is not the problem, replaying the events is. We cannot make a topic for each aggregate instance (per aggregate id). This is a limitation of Kafka (or Zookeeper, who to blame?). Therefore you would need to create one topic per aggregate type. For example a topic called `user` will contain all the user events. By doing so I only see two possible solutions (which have their problems) to make this work:

- Read the events in a background process and keep the aggregate state per aggregate instance in memory. If you have a lot of aggregates you'll run out of memory
- When writing the events to Kafka, write the current state to a local key-value store. All the aggregate event writers in the cluster read the topic to update their local key-value store. However when the aggregate actor gets spawned on another node we cannot be sure if the state we are loading is the latest state if we are using a local key-value store, since it is eventual consistency (reading)
- When writing the events to Kafka, write the current state to transactional consistent database. Whenever the actor is spawned on a different node, it doesn't suffer from the eventual consistency issue. To make this work correctly, we'll need a two-phase commit (2PC), since we are persisting to two databases. Using 2PC, we'll pay a performance cost, which is not what we want!

That's why we are using akka-persistence with Cassandara (but you could also use a JDBC database).

### Read side

We can use Kafka Connect to let a query continiously run against Cassandra or a JDBC database. By doing so we poll new events and put them on to a topic. This topic can be read by a consumer (microservice) to build up local or global state.

You could consider using Kafka-streams for that matter, but I am currently experimenting with several Scala based solutions to create the same semantics as Kafka-streams.

## Conclusion

Using CQRS and Event Sourcing to do microservices feels very natural. I hope you liked my article and in case you are looking for help on this matter, feel free to contact me. Maybe I can be of help to you!
