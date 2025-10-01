# Future Tasks for Recall Game Integration

## 🎯 Current Status: Status Mapping Fixed ✅

**COMPLETED**: Player status mapping from Dart camelCase to Flutter snake_case is now working correctly.

**Evidence from logs**:
- Computer player: `status: initial_peek` ✅ (was showing "unknown")
- User player: `status: initial_peek` ✅ (was showing "waiting")
- No more frontend validation errors ✅

---

## 📋 Future Tasks Required

### 1. 🔄 Auto State Detection System

**Problem**: The system needs to automatically detect and update player states based on game events, similar to the old Python-only system.

**Current Issue**: 
- Players are stuck in `initial_peek` status
- No automatic transition to `ready` or `playing` status
- Missing automatic state progression logic

**Required Implementation**:
- [ ] **Auto State Detection**: Implement automatic player state transitions
- [ ] **Event-Driven Updates**: Hook into game events to trigger state changes
- [ ] **Status Progression Logic**: 
  - `initial_peek` → `ready` (after initial peek completed)
  - `ready` → `playing` (when turn starts)
  - `playing` → `waiting` (when turn ends)
- [ ] **Computer Player Auto-Actions**: Computer players should automatically complete their turns

**Files to Modify**:
- `game_event_coordinator.py` - Add auto state detection logic
- `game_round.dart` - Add automatic state transitions
- `game_state.dart` - Add state change triggers

### 2. ⏰ Initial Peek Timer System

**Problem**: The initial peek phase needs a timer that automatically transitions players to the next phase, just like the old system.

**Current Issue**:
- No timer for initial peek phase
- Players can stay in `initial_peek` indefinitely
- Missing automatic phase progression

**Required Implementation**:
- [ ] **10-Second Timer**: Add 10-second countdown for initial peek phase
- [ ] **Auto-Complete Logic**: Automatically complete initial peek for players who don't act
- [ ] **Timer UI**: Show countdown in frontend
- [ ] **Phase Transition**: Auto-advance to next game phase after timer expires
- [ ] **Status Updates**: Change player status from `initial_peek` to `ready` after timer

**Files to Modify**:
- `game_round.dart` - Add timer logic
- `game_event_coordinator.py` - Handle timer events
- Frontend widgets - Display timer countdown
- `recall_event_handler_callbacks.dart` - Handle timer events

### 3. 🔍 Status Change Detection

**Problem**: The system needs to detect when player status should change and automatically update it.

**Required Implementation**:
- [ ] **Status Change Triggers**: 
  - When player completes initial peek → `ready`
  - When player's turn starts → `playing`
  - When player's turn ends → `waiting`
  - When player wins → `winner`
  - When player disconnects → `disconnected`
- [ ] **Event Broadcasting**: Send status updates to all players
- [ ] **Frontend Updates**: Update UI to reflect status changes

**Files to Modify**:
- `game_round.dart` - Add status change detection
- `game_event_coordinator.py` - Broadcast status changes
- `recall_event_handler_callbacks.dart` - Handle status updates

---

## 🔧 Implementation Priority

### Phase 1: Auto State Detection (HIGH PRIORITY)
1. Implement automatic state transitions in Dart game logic
2. Add event-driven status updates
3. Test with computer players

### Phase 2: Initial Peek Timer (MEDIUM PRIORITY)
1. Add 10-second timer to initial peek phase
2. Implement auto-complete logic
3. Add frontend timer display

### Phase 3: Status Change Detection (MEDIUM PRIORITY)
1. Add comprehensive status change triggers
2. Implement event broadcasting
3. Test all status transitions

---

## 📊 Current Working Features

✅ **Status Mapping**: Dart camelCase → Flutter snake_case  
✅ **Dual Update Pattern**: Public + private state updates  
✅ **Computer Player Hands**: Visible in public game state  
✅ **User Player Hands**: Populated from public game state  
✅ **Auto Computer Player Addition**: Working correctly  
✅ **Start Match Logic**: Replicated old system behavior  

---

## 🐛 Known Issues

❌ **Auto State Detection**: Players stuck in `initial_peek` status  
❌ **Initial Peek Timer**: No automatic timer for phase progression  
❌ **Status Transitions**: Missing automatic status change logic  
❌ **Computer Player Actions**: No automatic turn completion  

---

## 📝 Notes from Old System Analysis

**Old Python System Had**:
- Automatic status transitions based on game events
- 10-second timer for initial peek phase
- Auto-complete logic for inactive players
- Event-driven status updates
- Computer player auto-actions

**New Hybrid System Needs**:
- Same automatic behavior as old system
- Dart game logic should handle state transitions
- Python coordinator should broadcast changes
- Frontend should display status changes

---

## 🎯 Next Steps

1. **Immediate**: Test current status mapping fix
2. **Short-term**: Implement auto state detection
3. **Medium-term**: Add initial peek timer
4. **Long-term**: Complete status change detection system

**Ready for testing the current status fix!** 🚀
