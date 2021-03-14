function tasks = new_task(commands, varargin)
commands = reshape(commands,1,[]);
char_varargin = cellfun(@(x) char(x), varargin, 'UniformOutput', false);

tasks = cell(0);
if ~iscell(commands)
    commands = {commands};
end

if any(strcmpi('addpath', char_varargin))
    path2add = char_varargin{find(strcmpi('addpath', char_varargin), 1) + 1};
else
    path2add = 'None';
end

for i = 1:length(commands)
    command = char(commands{i});
    task = struct();
    task.command = command;
    task.created_by = [getenv('COMPUTERNAME'), '/', getenv('USERNAME')];
    task.created_on = datetime();
    task.path2add = path2add;
    tasks{i} = task;
end

else
end

lua_add_task = ['"'...
    'local task_id = redis.call(''incr'',''tasks_count'');' ...
    'local task_key = ''task:'' .. task_id ;' ...
    'redis.call(''RPUSH'', ''pending_tasks'', task_key);' ...
    'redis.call(''HMSET'', task_key, ' ...
    '''key'', task_key, ' ...
    '''id'', task_id, '...
    '''command'', KEYS[1], ' ...
    '''created_by'', KEYS[2], ' ...
    '''created_on'', KEYS[3], ' ...
    '''path2add'', KEYS[4], ' ...
    '''status'', ''pending'');'...
    'return task_key'...
    '" 4'];
redis_add_task = @(task) ['eval ' lua_add_task ...
    ' ' str_to_redis_str(task.command) ...
    ' ' str_to_redis_str(task.created_by) ...
    ' ' str_to_redis_str(task.created_on) ...
    ' ' str_to_redis_str(task.path2add) ];
cmds = cellfun(redis_add_task, tasks, 'UniformOutput', false);
keys = mrc.redis_cmd(cmds);

if any(strcmpi('wait', varargin))
    mrc.wait(keys);
end
    
if length(tasks)==1
    tasks = tasks{1};
end

end

