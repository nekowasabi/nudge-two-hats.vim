# nudge-two-hats.vim
<img src="https://github.com/user-attachments/assets/8f22c6fb-18cf-4c71-ae80-489829ebd9c6" width="30%">

A plugin that nudges you with AI about which hat you are wearing and what you should do in the situation.

Inspired by [An example of preparatory refactoring](https://martinfowler.com/articles/preparatory-refactoring-example.html)

## Features

- Monitors your code changes in real-time
- Uses Gemini AI to analyze which "hat" you're wearing (refactoring or feature development)
- Provides concise 10-character advice via notifications
- Toggle functionality on/off as needed

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nekowasabi/nudge-two-hats.vim",
  config = function()
    require("nudge-two-hats").setup({
      -- Optional configuration
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "nekowasabi/nudge-two-hats.vim",
  config = function()
    require("nudge-two-hats").setup()
  end
}
```

## Configuration

```lua
require("nudge-two-hats").setup({
  system_prompt = "Give a 10-character advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  execution_delay = 60000, -- Delay in milliseconds (1 minute)
  min_interval = 60, -- Minimum interval between API calls in seconds
  gemini_model = "gemini-2.5-flash-preview-04-17", -- Model to use
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent",
})
```

## Usage

1. Set your Gemini API key (two options):
   - Set the GEMINI_API_KEY environment variable (recommended)
   - Or use the command: `:NudgeTwoHatsSetApiKey YOUR_API_KEY`

2. Start monitoring the current buffer:
```
:NudgeTwoHatsStart
```

3. Toggle the plugin on/off:
```
:NudgeTwoHatsToggle
```

## Requirements

- Neovim 0.7.0+
- Gemini API key
