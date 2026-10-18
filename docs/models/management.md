# Model Management

The provider exposes LM Studio's native model-management endpoints, so you can
control what is in memory without shelling out to `lms`:

```ruby
provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)

provider.native_models   # every downloaded model, with architecture,
                         # quantization, capabilities, loaded_instances, ...
provider.loaded_models   # just the ones resident in memory

instance = provider.load_model('qwen/qwen3-4b', context_length: 8192)
# => { "instance_id" => "qwen/qwen3-4b", "status" => "loaded", ... }
provider.unload_model(instance['instance_id'])

provider.download_model('qwen/qwen3-4b')  # fetch a new model onto disk
```

| Method | Endpoint | Returns |
| --- | --- | --- |
| `native_models` | `GET /api/v1/models` | every downloaded model as LM Studio describes it, as an Array of Hashes |
| `loaded_models` | `GET /api/v1/models` | the subset with at least one loaded instance |
| `load_model(model, context_length: nil, **options)` | `POST /api/v1/models/load` | the server's response Hash, including `instance_id` |
| `unload_model(instance_id)` | `POST /api/v1/models/unload` | the server's response Hash |
| `download_model(model, **options)` | `POST /api/v1/models/download` | the server's response Hash |

Extra keyword options go into the request as-is; the server rejects keys it
doesn't know.

## Instances

`load_model` returns the `instance_id` that `unload_model` takes. Loading a
model that is already resident starts a **second instance** (`...:2`), so hold
on to the id you were given.

For the same reason these calls are sent non-idempotent: RubyLLM retries a POST
that times out, and a retried load of a large model would hold the weights in
memory twice.

The same thing can happen behind your back with decision models: a model you
loaded yourself, then requested on demand by a judgment, can end up with two
instances. See [Decision Models](../judgments/decision-models.md#loading-and-memory).

## TTL

`ttl` is not a load option on the native API. Set idle TTL per request through
the OpenAI endpoints (the `ttl`
[request extra](../protocols/openai.md#lm-studio-request-extras)) or with
`lms load --ttl`.

Example `14_model_management.rb` lists, loads and unloads a model.
