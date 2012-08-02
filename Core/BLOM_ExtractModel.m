%> @file BLOM_ExtractModel.m
%> @brief BLOM 2.0 Outline based on what we discussed previously

%> Overview of BLOM Extract Model Structure
%> - Find all Input, External, Constraint and Cost BLOM library blocks.
%> - Build cost and constraint dependency wire graph, starting from Constraint and Cost blocks and traverse backwards.
%>     -  BFS to find the graph.
%>     -  Recognize reaching non-BLOM inputs (user error).
%>     -  Format of the graph: Sparse connectivity matrix of all wires, 
%>         store just the block handles.
%>     -  Each wire has a property whether optimization variables is
%>             introduced for it for each derivative evaluation, 
%>         intermediate major time step, initial time, final time.
%>     -  Store for each wire, if it is constrained, cost (discrete or continuous), 
%>         input, external.
%> - Flatten the wires:
%>     -  "Fetch" all PolyBlocks data: variables from the base workspace or values from the dialog (just do evalin('base',get_param(h,'A')).
%>     -  Get all possible dimensions (with or without the Simulink "compile"). 
%>     -  Translate all supported Simulink blocks to PolyBlocks using the known dimensions.   
%>     -  Eliminate duplicate routing variables. 
%>     -  Combine all PolyBlocks to a large P and K matrices.
%>     -  Eliminate whatever is possible (constants, identity PolyBlocks, linearly dependent constraints, replicated P rows, unused terms).
%>     -  Propagate time property information using the processed P and K structure.    
%> - Create the whole problem:
%>     -  Introduce and duplicate all major time step variables, including their dependencies.
%>     -  Introduce and duplicate minor time steps variables and their dependencies.
%>     -  Link by the appropriate Butcher tableau values major and minor time steps variables.
%>     -  Add move blocking constraints.
%>     -  Eliminate whatever is possible.
%>     -  Mark external, input.
%>     -  Take care of cost.

%======================================================================
%> @brief This function extracts a Simulink model and is the first step
%> into converting it into an optimization problem
%>
%> Examples:
%>   ModelSpec = BLOM_ExportModel; 
%>       Converts current active model.
%>
%>   ModelSpec = BLOM_ExportModel('Sys',10,0.5);  
%>       Converts current model 'Sys', with a a time step of 0.5 sec and 10 time steps.
%>   ModelSpec = BLOM_ExportModel('Sys',10,0.5,);  
%>       Converts current model 'Sys', with a a time step of 0.5 sec and 10 time steps, 
%>       assuming discrete model.
%>
%>   ModelSpec = BLOM_ExportModel('Sys',10,0.5,'Trapez');  
%>       Converts current model 'Sys', with a a time step of 0.5 sec ,10
%>       time steps and trapezoidal discretization method.
%>
%> @param name name of the model to convert
%> @param horizon integer number of steps in prediction horizon length, 1 if not
%> supplied
%> @param dt time step size [s], 1 if not supplied
%> @param disc discretization method {'none,'Euler','Trapez','RK4'}
%> @param options options created by BLOM_opset function
%>
%> @retval out1 return value for the first output variable
%> @retval out2 return value for the second output variable
%======================================================================

function [ModelSpec] = BLOM_ExtractModel(name,horizon,dt,integ_method,options)
    [boundHandles,costHandles,inputAndExternalHandles] = findBlocks(name);
    [outportHandles,boundStruct,stop] = ...
        searchSources(boundHandles,costHandles,inputAndExternalHandles);
    % FIX: should implement something that stops the code after analyzing
    % all the blocks and finding an error in the structure of the model
    if stop == 1
        % break the code somehow?
    end
    
    % evaluate the model in order to get dimensions of all the outports
    eval(['testBFS' '([],[],[],''compile'');']); 
    [optimVar,polyStruct,blocks] = makeStruct(outportHandles,name);
%     blocks.names
%     blocks.handles
%     polyStruct.block
%     polyStruct.P
%     polyStruct.K
    optimVar.block
    optimVar.index
    % find out which wires are relevant at which times
    [timeStruct] = relevantTimes(outportHandles);
    %following code is to make sure searchSources works
    length(blocks.handles)
    length(boundStruct.outportHandles)
    lengthOutport = length(outportHandles);
    for i = 1:length(outportHandles);
        parent = get_param(boundStruct.outportHandles(i),'Parent');
        portType = get_param(outportHandles(i),'PortType');
    end
    % just a placeholder for ModelSpec so that MATLAB does not complain
    ModelSpec = 1;
end

%%
%======================================================================
%> @brief Finds all Input, External, Constraint and Cost BLOM library
%> blocks
%>
%> More detailed description of the problem.
%>
%> @param name Name of the simulink model
%>
%> @retval blockHandles handles of all the relevant blocks
%======================================================================

function [boundHandles,costHandles,inputAndExternalHandles] = findBlocks(name)
    % FindAll may not be the most efficient way to find the handles
    boundHandles = [find_system(name,'FindAll','on','ReferenceBlock','BLOM_Lib/Bound')];
    costHandles = [find_system(name,'FindAll','on','ReferenceBlock','BLOM_Lib/DiscreteCost')];
    inputAndExternalHandles = ...
        [...find_system(name,'FindAll','on','ReferenceBlock','BLOM_Lib/InputFromWorkspace'); ...
        find_system(name,'FindAll','on','ReferenceBlock','BLOM_Lib/InputFromSimulink'); ...
        ...find_system(name,'FindAll','on','ReferenceBlock','BLOM_Lib/ExternalFromWorkspace'); ...
        find_system(name,'FindAll','on','ReferenceBlock','BLOM_Lib/ExternalFromSimulink')];
end

%%
%======================================================================
%> @brief Find all connected source blocks using a breadth first search.
%> Includes the handles already given.
%>
%> More detailed description of the problem.
%>
%> @param handleArray the array of handles that you want to search. These
%> are the block handles of the costs and constraints
%> @param varargin the external and input from simulink handles. the
%> sources of these blocks are not relevant to the optimization problem
%>
%> @retval sourceHandles return all the handles connected to input handles
%> @retval stop if there are any unconnected blocks or blocks that BLOM
%> does not support, this parameter gives a 1 to indicate true and 0 to
%> indicate false
%> @retval boundsStruct structure with fields: 1) outport handles found, 2)
%> boolean true or false if it is connected to a bounds block
%======================================================================

function [outportHandles,boundStruct,stop] = ...
    searchSources(boundHandles,costHandles,varargin)
    % only flag stop = 1 when there is a bad block
    stop = 0;
    if ~isempty(varargin)
        % gets blocks of final stopping places
        fromSimulink = varargin{1};
        fromSimulinkPorts = get_param(fromSimulink,'PortHandles');
        sOutportHandles = zeros(length(fromSimulinkPorts),1);
        sOutportIdx = 1;
        % add all the outport handles of the fromSimulink blocks. The BFS
        % will stop at these handles
        for idx = 1:length(fromSimulinkPorts);
            currentOutports = fromSimulinkPorts{idx}.Outport;
            sOutportLength = length(currentOutports);
            sOutportHandles(sOutportIdx:(sOutportIdx+sOutportLength-1)) = ...
                currentOutports;
            sOutportIdx = sOutportIdx+sOutportLength;
        end

    end
    
    % find all lines connected to costs and bounds and then get outport
    % ports from there
    
    % iZero is index of first zero
    iZero = 1;
    outportHandles = zeros(20,1);    
    % get all outports connected to the bounds 
    for i = 1:length(boundHandles)
        portH = get_param(boundHandles(i),'PortHandles');
        % costs and bounds should only have one inport and line
        currentInport = portH.Inport;
        [outportHandles,iZero] = getOutports(currentInport,outportHandles,...
            iZero);
    end
    
    % create structure for bounds. fill entries up to iBounds with true.
    % These are all the outportHandles found so far and must have a bound
    iBounds = iZero-1;
    boundStruct.bound = true(iBounds,1);
    
    % get all outports connected to costs
    for i = 1:length(costHandles)
        portH = get_param(costHandles(i),'PortHandles');
        % costs and bounds should only have one inport and line
        currentInport = portH.Inport;
        [outportHandles,iZero] = getOutports(currentInport,outportHandles,...
            iZero);
    end
    
    % iOut is current handle we are looking at
	iOut = 1;
    while 1
        if outportHandles(iOut) == 0
            % all handles have been found and searched
            break
        elseif any(outportHandles(iOut)==sOutportHandles)
            % if the current handle is equal to any of the external or input
            % from simulink, then continue with the loop and do not look
            % for more branches from that block
            iOut = iOut+1;
            continue
        elseif iOut > length(outportHandles)
            % should not reach here, just in case
            break
        elseif ~outportHandles(end)==0
            % no more space for more handles, allocate more space
            outportHandles = [outportHandles; zeros(length(outportHandles)*2,1)];
        end
        
        sourceBlock = get_param(outportHandles(iOut),'Parent');
        sourcePorts = get_param(sourceBlock,'PortHandles');
        sourceInports = [sourcePorts.Inport];
        if length(sourceInports) > 1
            % currently do nothing special if there is more than one input
            % except look for what's connected. 
            % FIX: check to see which inports affect which outports
            [outportHandles,iZero] = getOutports(sourceInports,...
                outportHandles,iZero);
        elseif isempty(sourceInports)
            % if there are no inports, no need to search this outport
            % anymore
            iOut = iOut+1;
            continue
        else
            % in the case of one inport, it must affect the outport, so
            % find the relevant outports
            [outportHandles,iZero] = getOutports(sourceInports,...
                outportHandles,iZero);
        end
        % FIX: should check to see if BLOM supports the blocks that is
        % found right here
        iOut = iOut+1;
    end
    if any(outportHandles==0)
        outportHandles = outportHandles(1:iZero-1);
    end
    %check if any handles are -1 and remove them
    if any(outportHandles==-1)
        % FIX PRINT STATEMENT. NOT NECESSARILY TRUE
        fprintf('One or more of the blocks are missing a connection\n');
        stop = 1;
    end
    
    % FIX: need to find some way to remove all -1 handles. using setdiff
    % with [-1] reorders all the outport handles and puts it in ascending
    % order
    % outportHandles = setdiff(outportHandles,[-1]);
    
    % update boundStruct with all the outport handles and boolean values
    % for true and false
    boundStruct.bound = [boundStruct.bound; false(length(outportHandles)-iBounds,1)];
    boundStruct.outportHandles = outportHandles;
end

%======================================================================
%> @brief From given inports, see which outports are relevant
%>
%> More detailed description of the problem.
%>
%> @param inports inports of current source
%> @param existingOutports current outports found. used to check for
%> redundancy
%> @param iZero current index of the first zero 
%>
%> @retval outportHandles new outports found
%> @retval iZero updates current index of the first zero
%======================================================================

function [outportHandles,iZero] = getOutports(inports,existingOutports,iZero)
    outportHandles = existingOutports;
    for i = 1:length(inports);
        currentLine = get_param(inports(i),'Line');
        % this gives the all the outports connected to this line
        currentOutports = get_param(currentLine,'SrcPorthandle');
        outLength = length(currentOutports);
        % in case outportHandles is too short 
        if outLength > length(outportHandles)-iZero+1;
            if outlength > length(outportHandles)
                outportHandles = [outportHandles; zeros(outLength*2,1)];
            else
                outportHandles = [outportHandles; ...
                    zeros(length(outportHandles),1)];
            end
        end
        
        diff = setdiff(currentOutports,outportHandles);
        diffLength = length(diff);
        outportHandles(iZero:(diffLength+iZero-1)) = diff;
        iZero = iZero + diffLength;
    end
end

%%
%======================================================================
%> @brief Creates struct that says which outports are relevant at which
%> times
%>
%> More detailed description of the problem.
%>
%> @param outportHandles outportHandles found by searchSources
%>
%> @retval timeStruct structure with following fields. 1) outportHandles 2)
%> majorTimeStep 3) minorTimeStep
%======================================================================

function [timeStruct] = relevantTimes(outportHandles)
    timeStruct.outportHandles = outportHandles;
    % FIX: actually check where the time steps are relevant
    timeStruct.majorTimeStep = true(length(outportHandles),1);
    timeStruct.minorTimeStep = true(length(outportHandles),1);
end

%%
%======================================================================
%> @brief From outport list, create three different structures needed for
%> the optimization problem
%>
%> More detailed description of the problem.
%>
%> @param outportHandles outportHandles found by searchSources
%>
%> @retval timeStruct structure with following fields. 1) outportHandles 2)
%> majorTimeStep 3) minorTimeStep
%======================================================================

function [optimVar,polyStruct,blocks] = makeStruct(outportHandles,name)
    polyHandles = [find_system(name,'FindAll','on','ReferenceBlock',...
        'BLOM_Lib/Polyblock')];
    polyLength = length(polyHandles);
    
    % create structure to store P and K matricies
    polyStruct.block = cell(polyLength,1);
    polyStruct.P = cell(polyLength,1);
    polyStruct.K = cell(polyLength,1);
    polyIdx = 1;
    
    % structure for block names and handles
    blocks.names = cell(length(outportHandles),1);
    blocks.handles = zeros(length(outportHandles),1);
    blockZero = 1;
    
    % structure for optimization variables and handles
    optimVar.block = zeros(length(outportHandles),1);
    optimVar.index = zeros(length(outportHandles),1);
    optimZero = 1;
    for i = 1:length(outportHandles)
        currentBlockName = get_param(outportHandles(i),'Parent');
        currentBlockHandle = get_param(outportHandles(i),'ParentHandle');
        if ~any(blocks.handles==currentBlockHandle)
            % no duplicate blocks, add this block
            blocks.names{blockZero} = currentBlockName;
            blocks.handles(blockZero) = currentBlockHandle;
            blockZero = blockZero+1;
        end
        
        if any(polyHandles==currentBlockHandle)
            % store P&K matricies if the current block is a polyblock
            polyStruct.block{polyIdx} = blockZero-1;
            polyStruct.P{polyIdx} = eval(get_param(currentBlockHandle,'P'));
            polyStruct.K{polyIdx}= eval(get_param(currentBlockHandle,'K'));
            polyIdx = polyIdx +1;
        end
        
        % get dimensions of each outport and for each parameter, store this
        % in a structure
        currentDim = get_param(outportHandles(i),'CompiledPortDimensions');
        lengthOut = currentDim(1)*currentDim(2);
        currentIndices = 1:lengthOut;
        if (optimZero+lengthOut) > length(optimVar.block)
            % if the current length of optimvar is not enough, double the
            % size
            optimVar.block = [optimVar.block; zeros(length(optimVar.block),1)];
            optimVar.index = [optimVar.index; zeros(length(optimVar.index),1)];
        end
        % store the block and index
        optimVar.block(optimZero:(optimZero+lengthOut-1)) = blockZero-1;
        optimVar.index(optimZero:(optimZero+lengthOut-1)) = currentIndices;
        optimZero = optimZero+lengthOut;
        
    end
    
    blocks.names = blocks.names(1:blockZero-1);
    blocks.handles = blocks.handles(1:blockZero-1);
    optimVar.block = optimVar.block(1:optimZero-1);
    optimVar.index = optimVar.index(1:optimZero-1);
end

% function [sourceHandles,stop] = searchSources(handleArray,varargin)
%     if ~isempty(varargin)
%         fromSimulink = varargin{1};
%     end
%     % i = current handle that we're looking at
%     i = 1;
%     sourceHandles = zeros(2,1);
%     % j is the index of the first zero
%     j = length(handleArray)+1;
%     sourceHandles(1:length(handleArray)) = handleArray;
%     while 1
%         if sourceHandles(i) == 0
%             % when this is true, all of the handles have been found
%             break
%         elseif any(fromSimulink==sourceHandles(i))
%             % if the current handle is equal to any of the external or input
%             % from simulink, then continue with the loop and do not look for
%             % more branches from that block
%             i = i+1;
%             continue
%         elseif i > length(sourceHandles)
%             break
%         elseif ~sourceHandles(end)==0
%             % if we reach the point where there's no more space for more
%             % handles, allocate more space
%             sourceHandles = [sourceHandles; zeros(length(sourceHandles)*2,1)];
%         end
%         ports = get_param(sourceHandles(i),'PortConnectivity');
%         % FIX: once we get all the handles, we will want to check whether
%         % or not BLOM will be able to process these blocks. 
%         sHandles = [ports.SrcBlock];
%         newHandles = setdiff(sHandles,sourceHandles);
%         if (j+length(newHandles)-1) >= length(sourceHandles)
%             % if there's not enough space for the new handles, allocate more
%             % space
%             sourceHandles = [sourceHandles; zeros(length(sourceHandles)*2,1)];
%         end
%         
%         if ~isempty(newHandles)
%             sourceHandles(j:(j+length(newHandles)-1)) = newHandles;
%             j = j + length(newHandles);
%         end
%         i = i + 1;
%     end
%     
%     if any(sourceHandles==0)
%         sourceHandles = sourceHandles(1:j-1);
%     end
%     %check if any handles are -1 and remove them
%     if any(sourceHandles==-1)
%         fprintf('One or more of the blocks are missing a connection\n');
%         stop = 1;
%     end
%     sourceHandles = setdiff([-1],sourceHandles);
% end
