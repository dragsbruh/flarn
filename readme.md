# flarn

its a markov chain trainer and runner

## installation

### requirements

- zig (recommended 0.14.1 or higher);

### compiling

```bash
zig build -Doptimize=ReleaseFast
```

this will build a release executable at `./zig-out/bin/flarn`

```bash
sudo install -Dm755 ./zig-out/bin/flarn /usr/bin/flarn
```

this will copy the binary to `/usr/bin/flarn` so you can use it anywhere. otherwise you can just call with direct path.

## usage

all you need is text files. you can just dump all text files in a directory lets call it `data`.

```bash
data/
  story1.txt
  story2.txt
  book/
    chapter1.txt
    chapter2.txt
```

create a file called `model.zon` beside it. you can use the template provided in [example.model.zon](./example.model.zon), or:

```zig
.{
    .depth = 8,
    .buffer_size = 8192,
    .paths = .{
      "data",
    },
}
```

it will go through every file (or walk through it if its a directory) and use that data for training.

zon is zig object notation, a json-like format but zig. theres no docs >w<

to actually start training, you can use:

```bash
flarn train ./model.zon ./model.flrn
```

this will train the model and save it to `./model.flrn`.

to run the model, you can use:

```bash
flarn run ./model.flrn
```

this will generate text until it cant anymore.

## detailed

### terms

- `model` -> just markov chain
- `modelfile` -> the `.zon` file containing metadata (only used for training)
- saving the model -> just serializing the model so you can pretrain a model before running it. i recommend you use the `.flrn` extension for no particular reason.

### configuration

- `depth` is the depth of the markov chain, higher = generations are very similar to training data.

  increasing this also increases the memory usage and training times. i'd recommend you start with `4` or `6` and increase until `12`.
  above `12` its either using a lot of memory or just spitting out the exact same text.

  this might change if you have a lot of memory available and a lot of training data (a lot, i mean it)
  and you can go higher depths in that case.

- `buffer_size`

  during training the files arent read entirely but split into buffers. by default its 8kb (8192 bytes). increasing it is not necessarily better.

### training data

memory usage depends a little bit on the training data. you could theoretically just train it on raw binary, but if the data is more diverse, the memory usage increases a lot.

for example, simply lowercasing the training data can reduce memory usage by 50%.

splitting data into multiple files isnt beneficial either, its just the same.

## interactive mode

this is for programmatic usage of flarn.

currently you can only use one model with one flarn process, just open multiple if you need multiple models, its almost the same memory usage anyway.
you can have multiple streaming concurrent outputs from a single flarn process.

to start interactive mode, you can run

```bash
flarn it ./model.flrn
```

you send commands via stdin and receive generations/output from stdout.
error messages are sent plaintext to stderr, just as god intended.

the protocol is basically just newline separated strings of

```bash
command|argument1|argument2|...
```

### input

there are 3 commands you can send at any time:

**1. start generation session:**

```bash
c|<id>
```

where `id` is just an integer. its the id of the generation stream.
you can run this multiple times with different ids to create asynchronous (**not multi-threaded**) generation streams.

**2. stop generation:**

```bash
s|<id>
```

this will stop the generation that was started with that id (i.e., `c|<id>`)

**3. change token size:**

```bash
t|<token_size>
```

this will change the token size to specified value.
token size is just the size of each generation stream's chunk.
setting it too high might make it slower if youre using multiple generation streams.

by default this value is set to 4.

### output

its written to stdout in the same syntax, newline separated.

**1. informational:**

when you run commands such as `c|123` or `s|123` or `t|3`, these are emitted back as is.

`s|<id>` is also emitted when the generation stops by itself (because it cant find the node, might happen if depth is too high and training data cant match it)

**2. output:**

if there are active generations running, the output is streamed in chunks like this:

```bash
n|<id>|<output>
```

the id is the id of the session you started with `c|<id>`

output is escaped, here is pseudocode that might help.

```typescript
const escaped = escapeString(
  "the qu|ick brown\n \rfox jumped\tover the lazy dawg >w< \\|"
);
// the qu\|ick brown\u000a \u000dfox jumped\u0009over the lazy dawg >w< \\\|
```

the escaped string is used in `output`.

example escaping and unescaping functions (in typescript) are provided in [scripts/escape.ts](./scripts/escape.ts)
