Output demo.gif
Set FontSize 20
Set Width 900
Set Height 700
Set Theme "Catppuccin Mocha"
Set Padding 12

Hide
Type "alias mbox-diff=$MISE_PROJECT_ROOT/zig-out/bin/mbox-diff"
Enter
Type "cd $MISE_PROJECT_ROOT && zig build && cd src/tools/mbox-diff/demo && clear"
Enter
Wait
Show

# Create sample mbox files
Type "cat base.mbox"
Sleep 0.5s
Enter
Sleep 3s

Type "cat new.mbox"
Sleep 0.5s
Enter
Sleep 3s

# Run mbox-diff
Type "mbox-diff base.mbox new.mbox -o diff.mbox"
Sleep 0.5s
Enter
Sleep 2s

# Show the output
Type "cat diff.mbox"
Sleep 0.5s
Enter
Sleep 3s
