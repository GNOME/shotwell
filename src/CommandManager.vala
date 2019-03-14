/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public interface CommandDescription : Object {
   public abstract string get_name();
   
   public abstract string get_explanation();
}

// Command's overrideable action calls are guaranteed to be called in this order:
//
//   * prepare()
//   * execute() (once and only once)
//   * prepare()
//   * undo()
//   * prepare()
//   * redo()
//   * prepare()
//   * undo()
//   * prepare()
//   * redo() ...
//
// redo()'s default implementation is to call execute, which in many cases is appropriate.
public abstract class Command : Object, CommandDescription {
    private string name;
    private string explanation;
    private weak CommandManager manager = null;
    
    protected Command(string name, string explanation) {
        this.name = name;
        this.explanation = explanation;
    }
    
    ~Command() {
#if TRACE_DTORS
        debug("DTOR: Command %s (%s)", name, explanation);
#endif
    }
    
    public virtual void prepare() {
    }
    
    public abstract void execute();
    
    public abstract void undo();
    
    public virtual void redo() {
        execute();
    }
    
    // Command compression, allowing multiple commands of similar type to be undone/redone at the
    // same time.  If this method returns true, it's assumed the passed Command has been executed.
    public virtual bool compress(Command command) {
        return false;
    }
    
    public virtual string get_name() {
        return name;
    }
    
    public virtual string get_explanation() {
        return explanation;
    }
    
    public CommandManager? get_command_manager() {
        return manager;
    }
    
    // This should only be called by CommandManager.
    public void internal_set_command_manager(CommandManager manager) {
        assert(this.manager == null);
        
        this.manager = manager;
    }
}

public class CommandManager {
    public const int DEFAULT_DEPTH = 20;
    
    private int depth;
    private Gee.ArrayList<Command> undo_stack = new Gee.ArrayList<Command>();
    private Gee.ArrayList<Command> redo_stack = new Gee.ArrayList<Command>();
    
    public signal void altered(bool can_undo, bool can_redo);
    
    public CommandManager(int depth = DEFAULT_DEPTH) {
        assert(depth > 0);
        
        this.depth = depth;
    }
    
    public void reset() {
        undo_stack.clear();
        redo_stack.clear();
        
        altered(false, false);
    }
    
    public void execute(Command command) {
        // assign command to this manager
        command.internal_set_command_manager(this);
        
        // clear redo stack; executing a command implies not going to undo an undo
        redo_stack.clear();
        
        // see if this command can be compressed (merged) with the topmost command
        Command? top_command = top(undo_stack);
        if (top_command != null) {
            if (top_command.compress(command))
                return;
        }
        
        // update state before executing command
        push(undo_stack, command);
        
        command.prepare();
        command.execute();
        
        // notify after execution
        altered(can_undo(), can_redo());
    }
    
    public bool can_undo() {
        return undo_stack.size > 0;
    }
    
    public CommandDescription? get_undo_description() {
        return top(undo_stack);
    }
    
    public bool undo() {
        Command? command = pop(undo_stack);
        if (command == null)
            return false;
        
        // update state before execution
        push(redo_stack, command);
        
        // undo command with state ready
        command.prepare();
        command.undo();
        
        // report state changed after command has executed
        altered(can_undo(), can_redo());
        
        return true;
    }
    
    public bool can_redo() {
        return redo_stack.size > 0;
    }
    
    public CommandDescription? get_redo_description() {
        return top(redo_stack);
    }
    
    public bool redo() {
        Command? command = pop(redo_stack);
        if (command == null)
            return false;
        
        // update state before execution
        push(undo_stack, command);
        
        // redo command with state ready
        command.prepare();
        command.redo();
        
        // report state changed after command has executed
        altered(can_undo(), can_redo());
        
        return true;
    }
    
    private Command? top(Gee.ArrayList<Command> stack) {
        return (stack.size > 0) ? stack.get(stack.size - 1) : null;
    }
    
    private void push(Gee.ArrayList<Command> stack, Command command) {
        stack.add(command);
        
        // maintain a max depth
        while (stack.size >= depth)
            stack.remove_at(0);
    }
    
    private Command? pop(Gee.ArrayList<Command> stack) {
        if (stack.size <= 0)
            return null;
        
        Command command = stack.get(stack.size - 1);
        bool removed = stack.remove(command);
        assert(removed);
        
        return command;
    }
}

