---
name: cloudkit-schema-deploy
description: Steps to deploy the CloudKit schema to Production after any SwiftData model property is added, removed or retyped — required before every TestFlight/App Store build. Use when changing a model, preparing a release build, or diagnosing BAD_REQUEST / partialFailure (CKErrorDomain error 2) sync errors.
---

# Deploying the CloudKit schema

TestFlight and App Store builds talk to the **Production** CloudKit environment, which never
creates record types or fields on its own. Development does — but only for fields it has
actually seen exported, and a `CKRecord` carries no entry for a nil value. A field nobody
happened to populate while testing is therefore missing from *both* environments, so comparing
Development against Production shows no diff while Production is still behind the model. The
comparison that matters is model vs Production.

So, whenever a model property is added, removed or retyped:

1. Debug build (Simulator signed into iCloud) → hammer menu → **Validate CloudKit Schema**.
   Dry run; prints the complete record-type and field listing to the Xcode console.
2. Same menu → **Push CloudKit Schema (Dev)**. This runs `initializeCloudKitSchema`, which
   covers every entity and attribute from the model rather than from what got typed in.
3. CloudKit Console → Schema → **Deploy Schema Changes** to push Development to Production.
   Additive-only, so it cannot break existing production data.

Skipping this produces `BAD_REQUEST` in the CloudKit Console logs and, on the client, a
`partialFailure` — the bare `CKErrorDomain error 2`. `CloudKitSchemaInitializer` (DEBUG only)
holds the details.
