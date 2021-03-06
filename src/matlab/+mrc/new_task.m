function [task_keys, tasks] = new_task(commands, varargin)
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


if any(strcmpi('dependencies', char_varargin))
    dependencies = varargin{find(strcmpi('dependencies', char_varargin), 1) + 1};
    if ~iscell(dependencies)
        dependencies = {dependencies};
    end
    dependencies = char(join(dependencies(:)', ' '));
else
    dependencies = '';
end

redis_add_task = @(task) ['EVALSHA ' script_SHA('add_task') '4' ...
    ' ' str_to_redis_str(task.command) ...
    ' ' str_to_redis_str(task.created_by) ...
    ' ' str_to_redis_str(task.created_on) ...
    ' ' str_to_redis_str(task.path2add) ...
    ' ' dependencies];
cmds = cellfun(redis_add_task, tasks, 'UniformOutput', false);
task_keys = mrc.redis_cmd(cmds);

for task_idx = 1:numel(tasks)
    tasks{task_idx}.key = task_keys{task_idx};
end

if any(strcmpi('wait', varargin))
    mrc.wait(task_keys);
end
    
if length(tasks)==1
    tasks = tasks{1};
end

end

