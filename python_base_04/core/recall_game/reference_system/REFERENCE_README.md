# Declarations Reference System

## Overview

The Declarations Reference System automatically generates a comprehensive HTML reference page from all YAML declarations in the Recall game system. This provides a live, always-up-to-date reference for all game rules, effects, validations, and placeholders.

## Features

### 🎯 **Live Reference**
- Automatically scans all YAML files in the `game_rules/` directory
- Generates a comprehensive HTML reference page
- Updates automatically when you add, modify, or remove declarations

### 🔍 **Searchable**
- Real-time search functionality
- Search by declaration name, type, content, or placeholders
- Case-insensitive search with highlighting

### 📊 **Organized Sections**
- **Actions**: Player action processing rules
- **Cards**: Card-specific special abilities
- **Special Powers**: Additional power card rules
- **AI Logic**: Computer player decision making
- **Placeholders**: Dynamic value references
- **Effects**: State change operations
- **Validation**: Input validation checks
- **Triggers**: Rule activation conditions

### 🎨 **Beautiful Interface**
- Modern, responsive design
- Syntax highlighting for YAML content
- Placeholder highlighting
- Type-specific color coding
- Mobile-friendly layout

## Usage

### Quick Start

1. **Generate the reference:**
   ```bash
   cd python_base_04/core/recall_game
   python update_reference.py
   ```

2. **View in browser:**
   - The script will automatically open the HTML file in your default browser
   - Or manually open `game_rules/declarations_reference.html`

### Adding New Declarations

1. **Create your YAML file** in the appropriate directory:
   ```bash
   # Action rule
   game_rules/actions/my_new_action.yaml
   
   # Card rule
   game_rules/cards/my_new_card.yaml
   
   # Special power rule
   game_rules/special_powers/my_new_power.yaml
   
   # AI logic rule
   game_rules/ai_logic/medium/my_new_decision.yaml
   ```

2. **Update the reference:**
   ```bash
   python update_reference.py
   ```

3. **View your new declaration** in the HTML reference

### Example YAML Declaration

```yaml
# game_rules/actions/my_custom_action.yaml
action_type: "my_custom_action"
triggers:
  - condition: "is_player_turn"
    game_state: "player_turn"

validation:
  - check: "player_has_card"
    card_id: "{card_id}"

effects:
  - type: "move_card_to_discard"
    card_id: "{card_id}"

notifications:
  - type: "broadcast"
    event: "custom_action_performed"
    data:
      player_id: "{player_id}"
      card: "{card_data}"
```

## File Structure

```
recall_game/
├── game_rules/
│   ├── actions/                    # Action processing rules
│   │   ├── play_card.yaml
│   │   ├── call_recall.yaml
│   │   └── my_new_action.yaml     # ← Your new action
│   ├── cards/                      # Card special abilities
│   │   ├── queen.yaml
│   │   ├── jack.yaml
│   │   └── my_new_card.yaml       # ← Your new card
│   ├── special_powers/             # Additional powers
│   │   ├── steal_card.yaml
│   │   └── my_new_power.yaml      # ← Your new power
│   ├── ai_logic/                   # AI decision making
│   │   ├── easy/
│   │   ├── medium/
│   │   │   ├── play_card_decision.yaml
│   │   │   └── my_new_decision.yaml  # ← Your new AI rule
│   │   └── hard/
│   └── declarations_reference.html  # ← Generated reference
├── generate_declarations_reference.py  # Generator script
├── update_reference.py              # Update script
└── REFERENCE_README.md              # This file
```

## Reference Sections

### Actions Section
Shows all action processing rules with:
- **Triggers**: When the action can be performed
- **Validation**: Input validation checks
- **Effects**: State changes to apply
- **Notifications**: Events to broadcast

### Cards Section
Shows card-specific rules with:
- **Special Powers**: Card abilities
- **Play Conditions**: When cards can be played
- **Out-of-turn Play**: Special play rules

### Special Powers Section
Shows additional power card rules with:
- **Power Effects**: Special abilities
- **Validation**: Power usage validation
- **Execution**: How powers are executed

### AI Logic Section
Shows computer player decision making with:
- **Evaluation Factors**: Decision criteria
- **Decision Logic**: If-then rules
- **Default Actions**: Fallback behavior

### Placeholders Section
Reference for all available placeholders:
- `{player_id}`: Player performing action
- `{card_id}`: Card being played
- `{card_rank}`: Card rank
- `{out_of_turn}`: Out-of-turn flag
- `{card_data}`: Complete card info
- `{target_player_id}`: Target for special powers
- `{card_position}`: Card position in hand

### Effects Section
Reference for all available effects:
- `move_card_to_discard`: Move card to discard pile
- `replace_card_in_hand`: Draw replacement card
- `check_special_power`: Trigger special abilities
- `check_recall_opportunity`: Check Recall eligibility
- `next_player`: Move to next player

### Validation Section
Reference for all validation checks:
- `player_has_card`: Check card ownership
- `card_is_playable`: Check playability
- `is_player_turn`: Check turn order
- `card_in_hand`: Check card presence

### Triggers Section
Reference for all trigger conditions:
- `is_player_turn`: Player's turn
- `same_rank_card`: Same rank play
- `recall_called`: Recall active
- `has_low_point_card`: Low point cards
- `has_special_power_card`: Special power cards

## Search Functionality

The reference includes powerful search capabilities:

### Search by Type
- **Actions**: `play_card`, `call_recall`
- **Cards**: `queen`, `jack`, `ace`
- **Powers**: `steal_card`, `peek_at_card`
- **AI**: `medium`, `easy`, `hard`

### Search by Content
- **Effects**: `move_card_to_discard`
- **Validations**: `player_has_card`
- **Triggers**: `is_player_turn`
- **Placeholders**: `{player_id}`

### Search by Description
- **Keywords**: `special power`, `out of turn`
- **Concepts**: `validation`, `effect`, `trigger`

## Integration with Development

### Automatic Updates
The reference automatically updates when you:
- Add new YAML files
- Modify existing declarations
- Remove declaration files
- Change directory structure

### Development Workflow
1. **Create new declaration** in appropriate directory
2. **Run update script**: `python update_reference.py`
3. **View in browser** to verify your declaration
4. **Test your changes** in the game system
5. **Commit changes** to version control

### Best Practices
- **Use descriptive names** for YAML files
- **Follow the established structure** for each type
- **Include comprehensive descriptions** in comments
- **Test declarations** before committing
- **Update reference** after any changes

## Customization

### Adding New Sections
To add new reference sections:

1. **Modify the generator** in `generate_declarations_reference.py`
2. **Add new section method** (e.g., `_get_custom_section()`)
3. **Update the main HTML generation**
4. **Add navigation link**

### Styling Changes
The HTML uses CSS for styling. Modify the `<style>` section in `generate_declarations_reference.py` to customize:
- Colors and themes
- Layout and spacing
- Typography
- Responsive design

### Search Enhancements
The search functionality uses JavaScript. Modify the `<script>` section to add:
- Advanced search filters
- Search history
- Search suggestions
- Export functionality

## Troubleshooting

### Reference Not Updating
```bash
# Check if YAML files are valid
python -c "import yaml; yaml.safe_load(open('game_rules/actions/play_card.yaml'))"

# Regenerate reference
python update_reference.py
```

### Missing Declarations
```bash
# Check file structure
ls -la game_rules/*/

# Verify YAML syntax
find game_rules/ -name "*.yaml" -exec python -c "import yaml; yaml.safe_load(open('{}'))" \;
```

### Browser Issues
- **File not opening**: Check file permissions
- **Styling issues**: Clear browser cache
- **Search not working**: Check JavaScript console

## Future Enhancements

### Planned Features
- **Export to PDF**: Generate PDF versions
- **API Documentation**: Include code examples
- **Version History**: Track declaration changes
- **Validation Testing**: Test declaration syntax
- **Auto-refresh**: Watch for file changes

### Integration Ideas
- **IDE Integration**: VS Code extension
- **Git Hooks**: Auto-update on commit
- **CI/CD Integration**: Build-time validation
- **Documentation Sync**: Auto-sync with main docs

## Contributing

When adding new declarations:

1. **Follow the established patterns**
2. **Include comprehensive documentation**
3. **Test thoroughly before committing**
4. **Update the reference**
5. **Add examples to this README**

## Support

For issues with the reference system:
- Check YAML syntax
- Verify file structure
- Regenerate reference
- Check browser console for errors

The declarations reference system provides a powerful, always-up-to-date way to understand and work with the Recall game's declarative rule system! 🎮✨ 