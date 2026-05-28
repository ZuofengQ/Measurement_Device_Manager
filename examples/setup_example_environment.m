function outputFolder = setup_example_environment()
rootDir = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(rootDir));

outputFolder = fullfile(rootDir, 'output');
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end
end
