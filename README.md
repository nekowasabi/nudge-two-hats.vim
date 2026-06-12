# nudge-two-hats.vim

Display a short nudge message when the cursor has been idle for a while.
Messages come from your own config — the plugin itself just handles
display (`vim.notify` and inline virtual text).

Based on [Nudge theory](https://en.wikipedia.org/wiki/Nudge_theory).

> **Breaking change**: previous versions called OpenRouter / Gemini to
> generate advice. That behavior is gone. Inject messages yourself through
> the `message` option.

## Requirements

- Neovim 0.7.0+

## Installation

### lazy.nvim

```lua
{
  "nekowasabi/nudge-two-hats.vim",
  config = function()
    require("nudge-two-hats").setup({
      notification = {
        idle_seconds = 300,
        message = function(ctx)
          return "You are wearing the refactoring hat."
        end,
      },
      virtual_text = {
        idle_seconds = 60,
        message = function(ctx)
          return "keep it simple"
        end,
      },
    })
  end,
}
```

## Configuration

Everything is optional. The defaults below are shown for reference.

```lua
require("nudge-two-hats").setup({
  debug = false,

  notification = {
    enabled      = true,
    idle_seconds = 300,   -- show after the cursor has been idle this long
    message      = nil,   -- required if enabled
    title        = "Nudge Two Hats",
    icon         = "🎩",
  },

  virtual_text = {
    enabled          = true,
    idle_seconds     = 60,
    message          = nil,
    position         = "right_align", -- "eol" | "right_align" | "overlay"
    text_color       = "#AABBCC",
    background_color = "#112233",
  },
})
```

### Message provider

Each channel has its own `message`. It accepts either a Lua function or a
Vim script function name, and is invoked with a context table:

```lua
ctx = {
  buf      = <bufnr>,
  filetype = "lua",
  channel  = "notification", -- or "virtual_text"
  cursor   = { line = 12, col = 0 }, -- 1-based line, 0-based col
}
```

Return a `string` to display, or `nil` to skip this nudge.

#### Lua function

```lua
require("nudge-two-hats").setup({
  notification = {
    message = function(ctx)
      if ctx.filetype == "markdown" then
        return "Focus on structure."
      end
      return "Which hat are you wearing?"
    end,
  },
})
```

#### Vim script function

```lua
require("nudge-two-hats").setup({
  virtual_text = { message = "MyNudgeMessage" },
})
```

```vim
function! MyNudgeMessage(ctx) abort
  return a:ctx.channel ==# 'virtual_text' ? 'keep going' : 'take a break'
endfunction
```

If the string does not match any Vim function name, it is treated as a
literal message.

### Message provider: Hermes Agent integration

You can use [Hermes Agent](https://github.com/NousResearch/hermes-agent) to
generate contextual nudges. Hermes reads `~/.hermes/SOUL.md`
(global personality), `~/.hermes/memories/` (persistent memory), and project
context files (`.hermes.md`, `AGENTS.md`, `CLAUDE.md`, `.cursorrules`)
automatically — the nudge side just needs to call it.

#### Synchronous (blocks Neovim)

```lua
local function hermes_nudge(ctx)
  local cwd = vim.fn.getcwd()
  local prompt = ("Give me a short nudge (1-2 sentences) to stay focused while coding %s.")
    :format(ctx.filetype or "")
  local result = vim.fn.system(
    "cd " .. vim.fn.shellescape(cwd)
    .. " && hermes -z " .. vim.fn.shellescape(prompt)
  )
  if vim.v.shell_error == 0 and result ~= "" then
    return result:gsub("^%s+", ""):gsub("%s+$", "")
  end
  return nil
end

require("nudge-two-hats").setup({
  notification = {
    idle_seconds = 300,
    message = hermes_nudge,
  },
  virtual_text = {
    idle_seconds = 60,
    message = hermes_nudge,
  },
})
```

#### Asynchronous (non-blocking, recommended)

```lua
local function hermes_nudge_async(ctx)
  local cwd = vim.fn.getcwd()
  local filetype = ctx.filetype or ""
  local prompt = ("Give me a short nudge (1-2 sentences) to stay focused while coding %s.")
    :format(filetype)
  local channel = ctx.channel
  local callback = function(result)
    if result and result ~= "" then
      if channel == "notification" then
        vim.notify(result, vim.log.levels.INFO, {
          title = "Hermes Nudge",
          icon = "🎩",
        })
      else
        -- Virtual text is handled by nudge's display module;
        -- the message function return value is used for that.
        -- To use async, set message to nil and handle display manually.
      end
    end
  end

  local cmd = {
    "bash", "-c",
    "cd " .. vim.fn.shellescape(cwd) .. " && hermes -z " .. vim.fn.shellescape(prompt),
  }
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local result = table.concat(data or {}, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      if result ~= "" then
        vim.schedule(function()
          callback(result)
        end)
      end
    end,
  })
  return nil -- return nil so nudge doesn't wait; async path handles display
end
```

> **Note**: The async approach requires the message function to return `nil`
> (skipping nudge's built-in display) and handle notification yourself.
> For virtual text, synchronous mode is simpler since it integrates with
> nudge's inline display automatically.

#### Provider ecosystem

Hermes Agent supports 30+ LLM providers (OpenRouter, OpenAI, Anthropic,
Gemini, xAI, MiniMax, Kimi, z.ai/GLM, DeepSeek, etc.) via
`hermes model` or `hermes config set model <provider>/<model>`.
No code change needed in the nudge plugin — just configure Hermes.

Key CLI flags for one-shot use:

| Flag | Purpose |
| --- | --- |
| `-z` | Pure text response, no banner/spinner |
| `-q "..."` | One-shot prompt (`hermes chat -q`) |
| `--provider <name>` | Force a specific provider |
| `-m <model>` | Override the model for this run |
| `--ignore-rules` | Skip context files for an isolated prompt |

### Hermes Agent installation

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc
```

Then configure a model:

```bash
hermes model  # interactive
# or:
hermes config set model openrouter/anthropic/claude-sonnet-4.6
```

### Branching by filetype

There is no filetype-aware configuration surface. Branch inside your own
`message` function:

```lua
message = function(ctx)
  local by_ft = {
    lua      = "Is this the smallest change that works?",
    markdown = "Is the outline clear?",
    python   = "Type hints present?",
  }
  return by_ft[ctx.filetype]
end
```

## Commands

| Command | Description |
| --- | --- |
| `:NudgeTwoHatsEnable` | Turn the plugin on. |
| `:NudgeTwoHatsDisable` | Turn the plugin off. |
| `:NudgeTwoHatsToggle` | Toggle the plugin state. |
| `:NudgeTwoHatsNow [channel]` | Fire a nudge immediately (`notification` or `virtual_text`; both when omitted). |
| `:NudgeTwoHatsDebug` | Print runtime state. |

## How it works

1. `setup()` merges your options, installs global autocmds, and enables
   the plugin.
2. For every normal buffer you enter, an idle timer is started per
   channel.
3. When the cursor stops moving for `idle_seconds`, the channel's
   `message` provider is called and the result is displayed.
4. Any cursor movement clears the virtual text (if shown) and restarts
   both idle timers from zero.

There is no periodic interval, no AI call, no content diffing, and no
pause/resume state. One knob (`idle_seconds`) per channel is all you need.
