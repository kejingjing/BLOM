function BLOM_Setup(ipopt_dir)
% Function to easily compile BLOM_NLP for the first time. If called with no
% input arguments, use uigetdir (this will fail in a -nodisplay instance of
% Matlab). Otherwise take first input argument as path to Ipopt.

% mfilename('fullpath') returns the entire path to this script
% the first output of fileparts(ans) gives the path string, same as dirname in unix
BLOM_dir = fileparts(mfilename('fullpath'));


switch (computer)
    case {'PCWIN','PCWIN64'}
        which_shell = questdlg('MinGW or Cygwin?','','MinGW','Cygwin','');
    case  {'GLNX86','GLNXA64'}
        makefile = 'Makefile';
    case {'MACI','MACI64'}
        makefile = 'Makefile.mac';
end


if nargin==0
    disp('Pick an IPOPT folder that holds lib directory, press cancel for no IPOPT')
    ipopt_dir = uigetdir('','Pick an IPOPT folder that holds lib directory, press cancel for no IPOPT');
end
if ~isequal(ipopt_dir, 0) && ~isempty(ipopt_dir)
    if ispc
        % Replace backslashes in BLOM and Ipopt paths with forward slashes
        BLOM_dir = strrep(BLOM_dir, '\', '/');
        ipopt_dir = strrep(ipopt_dir, '\', '/');
        if strcmp(which_shell, 'MinGW')
            shell_dir = 'MinGW\msys\1.0';
            makefile = 'Makefile.mingw';
        elseif strcmp(which_shell, 'Cygwin')
            shell_dir = 'cygwin';
            makefile = 'Makefile';
            % Have to translate ipopt_dir into Cygwin /cygdrive/... format
            ipopt_dir = ['`cygpath "' ipopt_dir '"`'];
        else
            error('Invalid selection of shell')
        end
        disp(['Identify ' shell_dir '\bin folder that contains sh.exe'])
        shell_dir = uigetdir(['C:\' shell_dir '\bin'], ...
            ['Identify ' shell_dir '\bin folder that contains sh.exe']);
        if ~exist([shell_dir '\sh.exe'], 'file')
            warning(['Invalid selection of shell_dir=' shell_dir])
        else
            system([shell_dir '\sh --login -c "cd ' BLOM_dir '/BLOM_Ipopt; ' ...
                'make clean; make -f ' makefile ' all IPOPTPATH=' ipopt_dir '"']);
            
            if (~exist('BLOM_NLP.exe','file'))
                warning('Compilation of BLOM_NLP.exe failed. Check the screen for errors');
            else
                disp('-------------------------------------');
                disp('BLOM_NLP.exe was succesfully compiled');
                disp('-------------------------------------');
            end
        end
    else
        cur_dir = pwd;
        cd([BLOM_dir '/BLOM_Ipopt']);
        system('make clean');
        % Workaround for Macs, gfortran gets installed in /usr/local but Matlab
        % doesn't have /usr/local on the path unless it's started from a terminal
        [status result] = system('which gfortran');
        if isequal(makefile, 'Makefile.mac') && isempty(result)
            setenv('PATH',[getenv('PATH') pathsep '/usr/local/bin']);
        end
        if isequal(makefile, 'Makefile.mac')
            [status result] = system('echo $(readlink $(which gfortran))');
            result = [fileparts(fileparts(result)) '/lib'];
            system(['make -f ' makefile ' all IPOPTPATH=' ipopt_dir ...
                ' GFORTRANPATH=' result]);
        else
            system(['make -f ' makefile ' all IPOPTPATH=' ipopt_dir]);
        end
        
        if (~exist('BLOM_NLP','file'))
            warning('Compilation of BLOM_NLP failed. Check the screen for errors');
        else
            disp('---------------------------------');
            disp('BLOM_NLP was succesfully compiled');
            disp('---------------------------------');
        end
        cd(cur_dir)
    end
else
    if ~ischar(ipopt_dir)
        ipopt_dir = num2str(ipopt_dir);
    end
    warning(['Invalid selection of ipopt_dir=' ipopt_dir])
end