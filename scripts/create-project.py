"""Generate an Xcode project without requiring XcodeGen on the receiving Mac."""
from pathlib import Path
import hashlib
import re

root = Path(__file__).resolve().parents[1]
project = root / 'Flash4399.xcodeproj'
project.mkdir(exist_ok=True)

def uid(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()

objects = []
def obj(label, contents):
    contents = re.sub(r'(?<!\()\);', ',);', contents)
    objects.append(f'{uid(label)} = {{ {contents} }};')
    return uid(label)

sources = ['AppDelegate.swift', 'BrowserViewController.swift', 'RuntimeAssets.swift', 'GameAssets.swift']
for name in sources:
    obj(name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>";')
    obj('build-' + name, f'isa = PBXBuildFile; fileRef = {uid(name)};')
obj('resources', 'isa = PBXFileReference; lastKnownFileType = folder; path = WebAssets; sourceTree = "<group>";')
obj('build-resources', f'isa = PBXBuildFile; fileRef = {uid("resources")};')
obj('plist', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Flash4399.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('app-group', f'isa = PBXGroup; path = Flash4399; sourceTree = "<group>"; children = ({",".join(uid(s) for s in sources)}, {uid("resources")}, {uid("plist")});')
obj('products', f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = ({uid("product")});')
obj('root-group', f'isa = PBXGroup; sourceTree = "<group>"; children = ({uid("app-group")},{uid("products")});')
obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(uid("build-"+s) for s in sources)}); runOnlyForDeploymentPostprocessing = 0;')
obj('resource-phase', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("build-resources")}); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for level in ['project', 'target']:
    for mode in ['Debug', 'Release']:
        settings = ('CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 16.4; '
                    'SWIFT_VERSION = 5.0; ENABLE_USER_SCRIPT_SANDBOXING = YES;')
        if level == 'target':
            settings += (' PRODUCT_BUNDLE_IDENTIFIER = com.example.Flash4399; PRODUCT_NAME = "$(TARGET_NAME)"; '
                         'INFOPLIST_FILE = Flash4399/Info.plist; TARGETED_DEVICE_FAMILY = "1,2"; '
                         'CODE_SIGN_STYLE = Automatic; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; '
                         'SUPPORTS_MACCATALYST = NO; GENERATE_INFOPLIST_FILE = NO;')
        settings += (' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;'
                     if mode == 'Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
        obj(f'{level}-{mode}', f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};')
    obj(f'{level}-config', f'isa = XCConfigurationList; buildConfigurations = ({uid(level+"-Debug")},{uid(level+"-Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("target-config")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resource-phase")}); buildRules = (); dependencies = (); name = Flash4399; productName = Flash4399; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("project-config")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en, zh_CN, Base); mainGroup = {uid("root-group")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {uid("project")}; }}\n', encoding='utf8')
scheme = project / 'xcshareddata' / 'xcschemes'
scheme.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="Flash4399.app" BlueprintName="Flash4399" ReferencedContainer="container:Flash4399.xcodeproj"/>'
(scheme / 'Flash4399.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''', encoding='utf8')
print('Created', project)
