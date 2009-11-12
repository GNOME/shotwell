/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public interface CommandDescription : Object {
   public abstract string get_name();
   
   public abstract string get_explanation();
}

public abstract class Command : Object, CommandDescription {
    private string? name;
    private string? explanation;
    
    public Command(string? name = null, string? explanation = null) {
        this.name = name;
        this.explanation = explanation;
    }
    
    public abstract void execute();
    
    public abstract void undo();
    
    public virtual string get_name() {
        return (name != null) ? name : "";
    }
    
    public virtual string get_explanation() {
        return (explanation != null) ? explanation : "";
    }
}

public class CommandManager {
    public const int DEFAULT_DEPTH = 10;
    
    private int depth;
    private Gee.ArrayList<Command> undo_stack = new Gee.ArrayList<Command>();
    private Gee.ArrayList<Command> redo_stack = new Gee.ArrayList<Command>();
    
    public signal void state_altered(bool can_undo, bool can_redo);
    
    public CommandManager(int depth = DEFAULT_DEPTH) {
        assert(depth > 0);
        
        this.depth = depth;
    }
    
    public void reset() {
        undo_stack.clear();
        redo_stack.clear();
        
        state_altered(false, false);
    }
    
    public void execute(Command command) {
        // clear redo stack; executing a command implies not going to undo an undo
        redo_stack.clear();
        
        // update state before executing command
        push(undo_stack, command);
        
        command.execute();
        
        // notify after execution
        state_altered(can_undo(), can_redo());
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
        command.undo();
        
        // report state changed after command has executed
        state_altered(can_undo(), can_redo());
        
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
        command.execute();
        
        // report state changed after command has executed
        state_altered(can_undo(), can_redo());
        
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

