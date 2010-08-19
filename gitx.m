//
//  gitx.m
//  GitX
//
//  Created by Ciarán Walsh on 15/08/2008.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitBinary.h"
#import "PBEasyPipe.h"
#import "GitXScriptingConstants.h"
#import "GitX.h"



#pragma mark Commands handled locally

void usage(char const *programName)
{

	printf("Usage: %s (--help|--version|--git-path)\n", programName);
	printf("   or: %s (--commit)\n", programName);
	printf("   or: %s (--all|--local|--branch) [branch/tag]\n", programName);
	printf("   or: %s <revlist options>\n", programName);
	printf("   or: %s (--diff)\n", programName);
	printf("\n");
	printf("    -h, --help             print this help\n");
	printf("    -v, --version          prints version info for both GitX and git\n");
	printf("    --git-path             prints the path to the directory containing git\n");
	printf("\n");
	printf("Commit/Stage view\n");
	printf("    -c, --commit           start GitX in commit/stage mode\n");
	printf("\n");
	printf("Branch filter options\n");
	printf("    Add an optional branch or tag name to select that branch using the given branch filter\n");
	printf("\n");
	printf("    --all [branch]         view history for all branches\n");
	printf("    --local [branch]       view history for local branches only\n");
	printf("    --branch [branch]      view history for the selected branch only\n");
	printf("\n");
	printf("RevList options\n");
	printf("    See 'man git-log' and 'man git-rev-list' for options you can pass to gitx\n");
	printf("\n");
	printf("    <branch>               select specific branch or tag\n");
	printf("     -- <path(s)>          show commits touching paths\n");
	printf("    -S<string>             show commits that introduce or remove an instance of <string>\n");
	printf("\n");
	printf("Diff options\n");
	printf("    See 'man git-diff' for options you can pass to gitx --diff\n");
	printf("\n");
	printf("    -d, --diff [<common diff options>] <commit>{0,2} [--] [<path>...]\n");
	printf("                            shows the diff in a window in GitX\n");
	printf("    git diff [options] | gitx\n");
	printf("                            use gitx to pipe diff output to a GitX window\n");
	exit(1);
}

void version_info()
{
	NSString *version = [[[NSBundle bundleForClass:[PBGitBinary class]] infoDictionary] valueForKey:@"CFBundleVersion"];
	NSString *gitVersion = [[[NSBundle bundleForClass:[PBGitBinary class]] infoDictionary] valueForKey:@"CFBundleGitVersion"];
	printf("GitX version %s (%s)\n", [version UTF8String], [gitVersion UTF8String]);
	if ([PBGitBinary path])
		printf("Using git found at %s, version %s\n", [[PBGitBinary path] UTF8String], [[PBGitBinary version] UTF8String]);
	else
		printf("GitX cannot find a git binary\n");
	exit(1);
}

void git_path()
{
	if (![PBGitBinary path])
		exit(101);

	NSString *path = [[PBGitBinary path] stringByDeletingLastPathComponent];
	printf("%s\n", [path UTF8String]);
	exit(0);
}


#pragma mark -
#pragma mark Commands sent to GitX

void handleSTDINDiff()
{
	NSFileHandle *handle = [NSFileHandle fileHandleWithStandardInput];
	NSData *data = [handle readDataToEndOfFile];
	NSString *diff = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

	if (diff && [diff length] > 0) {
		GitXApplication *gitXApp = [SBApplication applicationWithBundleIdentifier:kGitXBundleIdentifier];
		[gitXApp showDiff:diff];
	}

	exit(0);
}

void handleDiffWithArguments(NSURL *repositoryURL, NSMutableArray *arguments)
{
	[arguments insertObject:@"diff" atIndex:0];

	int retValue = 1;
	NSString *diffOutput = [PBEasyPipe outputForCommand:[PBGitBinary path] withArgs:arguments inDir:[repositoryURL path] retValue:&retValue];
	if (retValue) {
		// if there is an error diffOutput should have the error output from git
		if (diffOutput)
			printf("%s\n", [diffOutput UTF8String]);
		else
			printf("Invalid diff command [%d]\n", retValue);
		exit(3);
	}

	GitXApplication *gitXApp = [SBApplication applicationWithBundleIdentifier:kGitXBundleIdentifier];
	[gitXApp showDiff:diffOutput];

	exit(0);
}

void handleOpenRepository(NSURL *repositoryURL, NSMutableArray *arguments)
{
	// if there are command line arguments send them to GitX through an Apple Event
	// the recordDescriptor will be stored in keyAEPropData inside the openDocument or openApplication event
	NSAppleEventDescriptor *recordDescriptor = nil;
	if ([arguments count]) {
		recordDescriptor = [NSAppleEventDescriptor recordDescriptor];

		NSAppleEventDescriptor *listDescriptor = [NSAppleEventDescriptor listDescriptor];
		uint listIndex = 1; // AppleEvent list descriptor's are one based
		for (NSString *argument in arguments)
			[listDescriptor insertDescriptor:[NSAppleEventDescriptor descriptorWithString:argument] atIndex:listIndex++];

		[recordDescriptor setParamDescriptor:listDescriptor forKeyword:kGitXAEKeyArgumentsList];

		// this is used as a double check in GitX
		NSAppleEventDescriptor *url = [NSAppleEventDescriptor descriptorWithString:[repositoryURL absoluteString]];
		[recordDescriptor setParamDescriptor:url forKeyword:typeFileURL];
	}

	// use NSWorkspace to open GitX and send the arguments
	// this allows the repository document to modify itself before it shows it's GUI
	BOOL didOpenURLs = [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:repositoryURL]
									   withAppBundleIdentifier:kGitXBundleIdentifier
													   options:0
								additionalEventParamDescriptor:recordDescriptor
											 launchIdentifiers:NULL];
	if (!didOpenURLs) {
		printf("Unable to open GitX.app\n");
		exit(2);
	}
}


#pragma mark -
#pragma mark main

NSURL *workingDirectoryURL()
{
	NSString *path = [[[NSProcessInfo processInfo] environment] objectForKey:@"PWD"];

	NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
	if (!url) {
		printf("Unable to create url to path: %s\n", [path UTF8String]);
		exit(2);
	}

	return url;
}

NSMutableArray *argumentsArray()
{
	NSMutableArray *arguments = [[[NSProcessInfo processInfo] arguments] mutableCopy];
	[arguments removeObjectAtIndex:0]; // url to executable path is not needed

	return arguments;
}

int main(int argc, const char** argv)
{
	if (argc >= 2 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h")))
		usage(argv[0]);
	if (argc >= 2 && (!strcmp(argv[1], "--version") || !strcmp(argv[1], "-v")))
		version_info();
	if (argc >= 2 && !strcmp(argv[1], "--git-path"))
		git_path();

	// From here on everything needs to access git, so make sure it's installed
	if (![PBGitBinary path]) {
		printf("%s\n", [[PBGitBinary notFoundError] cStringUsingEncoding:NSUTF8StringEncoding]);
		exit(2);
	}

	// gitx can be used to pipe diff output to be displayed in GitX
	if (!isatty(STDIN_FILENO) && fdopen(STDIN_FILENO, "r"))
		handleSTDINDiff();

	// From this point, we require a working directory and the arguments
	NSMutableArray *arguments = argumentsArray();
	NSURL *wdURL = workingDirectoryURL();

	if ([arguments count] > 0 && ([[arguments objectAtIndex:0] isEqualToString:@"--diff"] ||
								  [[arguments objectAtIndex:0] isEqualToString:@"-d"])) {
		[arguments removeObjectAtIndex:0];
		handleDiffWithArguments(wdURL, arguments);
	}

	// No commands handled by gitx, open the current dir in GitX with the arguments
	handleOpenRepository(wdURL, arguments);

	return 0;
}
