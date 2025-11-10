# Last Train

This repo contains the code and data for the game *Last Train*, a text-based turn-based RPG written in PowerShell for some unknown but presumably bad reason. (The reasons are because (A) I wanted to practice with complicated PowerShell code and (B) I wanted to prototype quickly and it's the fastest language for me to write in.)

## Game story

You wake up next to an idling locomotive knowing only four things:

- Your name
- The sun is your enemy.
- The world will end in 7 days.
- You must ASCEND.

The train will take you to ASCENSION. Everything beyond that is up to you.

## To Play

This game only runs in PowerShell 7+. You can install it [at the official GitHub repo](https://github.com/PowerShell/PowerShell/releases). Some parts of it might run in PowerShell 5, but I don't test it in 5 and imagine there are enough syntax differences that it won't work.

You'll probably have to unblock the files and/or run in Bypass execution policy mode, since I'm sure most computers won't like running random scripts you downloaded from the internet. `Set-ExecutionPolicy Bypass -Scope Process` should help, but to be honest I haven't tested this on any computer other than mine. This readme will be updated if/when that changes.

To start the game, run `game.ps1` in a PowerShell 7 terminal. You can optionally use the `-Slot` parameter to specify the save slot you want to load. There are other parameters for the main script, too, including cheat options. Read the function `Apply-CheatOptions` in `functions/NewGame.ps1` to learn more.

Data is all saved locally, in whatever directory you cloned this repo to (under the `saves` directory). No access or resources are required outside of the repo directory. No external modules are required.

The general controls are to type the option you want to select, then press `<enter>`. A blank prompt, like `> :`, means you should just press `<enter>` when you're ready to continue. To quit the game, press `Ctrl+C`. You can then load your latest save the next time you want to play.

### Cheats

You can use various cheat options by passing an array object into the `Cheats` parameter of `game.ps1`. For example: `./game.ps1 -Cheats @('healthy', 'speedy')`. You can also load one of several premade cheat files as the array - these are mostly designed to simulate starting in a different location than the start. For example, the `airport-start` cheat bundle can be loaded as such: `.\game.ps1 -Cheats (Get-Content .\data\cheats\airport-start.json | ConvertFrom-Json -AsHashtable)`.

For a full listing of all available cheat options, read the function `Apply-CheatOptions` in `functions/NewGame.ps1`.

## Still in progress

It's not done yet. If you run into a `todo` barrier, you've hit the end of the current content. I hope to finish it eventually, but no promises.

## Contributing

You certainly can, if you want. Please try to limit any contributions to bug reports or bug fixes, rather than anything relating to creative assets. Also, make sure the game runs with your changes and actually fixes whatever you wanted to fix. If I ever decide to add tests, make sure those pass too and whatever you changed is tested.

## License stuff

This repo contains content licensed under different terms.

You can use the contents of this repo to play the game or to contribute to this repo. Please don't use the creative content (characters, prose, setting, story, anything under the `data` directory, etc.) for any other purpose.

You can use the purely technical code, as long as it doesn't contain any creative content, under the terms of the MIT license (included as LICENSE.txt).
