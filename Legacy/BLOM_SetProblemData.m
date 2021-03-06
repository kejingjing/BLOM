function SolverStruct =  BLOM_SetProblemData(SolverStruct,ModelSpec,OptGuess, ExtVars, InitialStates,options)
%
%   SolverStruct =
%   BLOM_SetProblemData(SolverStruct,ModelSpec,ExtVars,FirstStates,InitialGuess,options)
%
%   Sets problem data for the solver.
%
% Input:
%   SolverStruct -  Solver description struct, created with BLOM_ExportToSolver.
%   ModelSpec    -  Model structure generatated by BLOM_ExtractModel.
%   OptGuess     -  Structure, or vector, with variables for an initial guess.
%   ExtVars      -  Structure, or vector, with external variables.
%   InitialStates-  Structure, or vector, with initial state variables.
%   options      -  Options created by BLOM_optset function.

if isstruct(ExtVars)
    vecExt = BLOM_ConvertStructToVector(ModelSpec.all_names_struct,ExtVars) ;
else
    vecExt = ExtVars;
end
if isstruct(InitialStates)
    vecStates = BLOM_ConvertStructToVector(ModelSpec.all_names_struct,InitialStates) ;
else
    vecStates = InitialStates;
end
if isstruct(OptGuess)
    x0 = BLOM_ConvertStructToVector(ModelSpec.all_names_struct,OptGuess) ;
else
    x0 = OptGuess;
end

switch lower(SolverStruct.solver)
    case 'fmincon'
        SolverStruct.prData = SolverStruct.pr;
        SolverStruct.prData.x0  = x0;
        % fix external vars
        SolverStruct.prData.lb(ModelSpec.ex_vars ~= 0) = ...
            vecExt(ModelSpec.ex_vars ~= 0);
        SolverStruct.prData.ub(ModelSpec.ex_vars ~= 0) = ...
            vecExt(ModelSpec.ex_vars ~= 0);
        % fix state vars
        SolverStruct.prData.lb(ModelSpec.all_state_vars ~= 0) = ...
            vecStates(ModelSpec.all_state_vars ~= 0);
        SolverStruct.prData.ub(ModelSpec.all_state_vars ~= 0) = ...
            vecStates(ModelSpec.all_state_vars ~= 0);
        
    case 'ipopt'
        
        vec = vecExt;
        vec(~isnan(vecStates)) = vecStates(~isnan(vecStates)); % merge states and external
        k=0;
        
        % use exactly the same variables mapping as stored in BLOM_ExportToSolver 
        % TODO: need to change this format (fixed.AAs{}) to something more efficient
        %{
        for i=1:length(SolverStruct.fixed_idx)
            k = k+1;
            fixed.AAs{k} = sparse(length(ModelSpec.all_names),2);
            fixed.AAs{k}(SolverStruct.fixed_idx(i),1)=1;
            fixed.Cs{k}(1) = -1;
            fixed.Cs{k}(2) = vec(SolverStruct.fixed_idx(i)) ;
        end
        Data = zeros(length(fixed.AAs),1);
        for i=1:length(fixed.AAs)
            Data(i) = fixed.Cs{i}(2);
        end
        if ~isequal(Data, vec(SolverStruct.fixed_idx))
            error('mismatch')
        end
        %}
        CreateIpoptDAT('test',vec(SolverStruct.fixed_idx),x0);
        
%         SolverStruc

    case 'linprog'
        SolverStruct.prData = SolverStruct.pr;
        SolverStruct.prData.x0  = x0;
        % fix external vars
        SolverStruct.prData.lb(ModelSpec.ex_vars ~= 0) = ...
            vecExt(ModelSpec.ex_vars ~= 0);
        SolverStruct.prData.ub(ModelSpec.ex_vars ~= 0) = ...
            vecExt(ModelSpec.ex_vars ~= 0);
        % fix state vars
        SolverStruct.prData.lb(ModelSpec.all_state_vars ~= 0) = ...
            vecStates(ModelSpec.all_state_vars ~= 0);
        SolverStruct.prData.ub(ModelSpec.all_state_vars ~= 0) = ...
            vecStates(ModelSpec.all_state_vars ~= 0);
end


