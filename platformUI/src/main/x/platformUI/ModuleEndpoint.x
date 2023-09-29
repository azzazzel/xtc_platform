import ecstasy.mgmt.Container;
import ecstasy.mgmt.ModuleRepository;
import ecstasy.mgmt.DirRepository;
import ecstasy.mgmt.LinkedRepository;

import ecstasy.reflect.ModuleTemplate;
import ecstasy.reflect.TypeTemplate;

import web.*;
import web.http.FormDataFile;

import common.model.AccountInfo;
import common.model.ModuleInfo;
import common.model.WebAppInfo;
import common.model.DependentModule;

/**
 * Dedicated service for hosting modules.
 */
@WebService("/module")
@LoginRequired
service ModuleEndpoint() {

    construct() {
        accountManager = ControllerConfig.accountManager;
        hostManager    = ControllerConfig.hostManager;
    }

    /**
     * The account manager.
     */
    private AccountManager accountManager;

    /**
     * The host manager.
     */
    private HostManager hostManager;

    /**
     * The current account name.
     */
    String accountName.get() {
        return session?.userId? : "";
    }

    /**
     * Returns a JSON map of all uploaded modules for given account.
     * Information comes from the AccountManager (the assumption is the Account manager maintains the
     * consistency between the DB and disk storage)
     */
    @Get("all")
    Map<String, ModuleInfo> getAvailable() {
        AccountInfo accountInfo;
        if (!(accountInfo := accountManager.getAccount(accountName))) {
            return new ListMap();
        }
        return accountInfo.modules;
    }

    /**
     * Handles a request to upload module(s) and performs the following
     *  - saves the file(s) to disk (TODO delegate to the AccountManager)
     *  - builds ModuleInfo for each module
     *  - attempt to resolve module(s) if resolveParam == True
     *  - stores the ModuleInfo(s) in the Account
     */
    @Post("upload")
    String[] uploadModule(@QueryParam("resolve") String resolveParam) {
        assert RequestIn request ?= this.request;

        String[] results = [];
        if (web.Body body ?= request.body) {
            Directory libDir = hostManager.ensureUserLibDirectory(accountName);

            @Inject Container.Linker linker;

            for (FormDataFile fileData : http.extractFileData(body)) {
                File file = libDir.fileFor(fileData.fileName);
                file.contents = fileData.contents;

                try {
                    ModuleTemplate template      = linker.loadFileTemplate(file).mainModule;
                    String         qualifiedName = template.qualifiedName + ".xtc";

                    // save the file
                    /* TODO move the file saving operation to the AccountManager manager
                            so it can maintain the consistency between the DB and disk */
                    if (qualifiedName != file.name) {
                        if (File fileOld := libDir.findFile(qualifiedName)) {
                            fileOld.delete();
                        }
                        if (file.renameTo(qualifiedName)) {
                            results += $|Stored "{fileData.fileName}" module as: "{template.qualifiedName}"
                                       ;
                        } else {
                            results += $|Invalid or duplicate module name: {template.qualifiedName}"
                                       ;
                        }
                    }

                    Boolean resolve = resolveParam == "true";

                    accountManager.addOrUpdateModule(accountName,
                        buildModuleInfo(libDir, template.qualifiedName, resolve));

                    updateDependant(libDir, template.qualifiedName, resolve);

                } catch (Exception e) {
                    file.delete();
                    results += $"Invalid module file {fileData.fileName.quoted()}: {e.message}";
                }
            }
        }
       return results;
    }

    /**
     * Handles a request to delete a module and performs the following
     *  - removes the ModuleInfo from the Account
     *  - deletes the file (TODO delegate to the AccountManager)
     *  - update ModuleInfos for each module that depends on the removed module
     */
    @Delete("/delete/{name}")
    HttpStatus deleteModule(String name) {
        AccountInfo accountInfo;
        if (!(accountInfo := accountManager.getAccount(accountName))) {
            return HttpStatus.Unauthorized;
        }
        if (WebAppInfo info := accountInfo.webApps.get(name)) {
            return HttpStatus.Conflict;
        } else {
            accountManager.removeModule(accountName, name);
            Directory libDir = hostManager.ensureUserLibDirectory(accountName);
            if (File|Directory f := libDir.find(name + ".xtc")) {
                if (f.is(File)) {
                    f.delete();
                    updateDependant(libDir, name, True);
                    return HttpStatus.OK;
                } else {
                    return HttpStatus.NotFound;
                }
            } else {
                return HttpStatus.NotFound;
            }
        }
    }

    /**
     * Handles a request to resolve a module
     */
    @Post("/resolve/{name}")
    HttpStatus resolve(String name) {
        Directory libDir = hostManager.ensureUserLibDirectory(accountName);
        @Inject Container.Linker linker;

        try {
            accountManager.addOrUpdateModule(accountName, buildModuleInfo(libDir, name, True));
            return HttpStatus.OK;
        } catch (Exception e) {
            @Inject Console console;
            console.print(e);
            return HttpStatus.InternalServerError;
        }
    }

    /**
     * Iterates over modules that depend on `name` and rebuilds their ModuleInfos
     */
    private void updateDependant(Directory libDir, String name, Boolean resolve) {
        if (AccountInfo accountInfo := accountManager.getAccount(accountName)) {
            for (ModuleInfo moduleInfo : accountInfo.modules.values) {
                for (DependentModule dependent : moduleInfo.dependents) {
                    if (dependent.name == name) {
                        accountManager.addOrUpdateModule(
                            accountName, buildModuleInfo(libDir, moduleInfo.name, resolve));
                        break;
                    }
                }
            }
        }
    }

    /**
     * Generates ModuleInfo for the specified module.
     *
     * @param resolve  pass `True` to resolve the module
     */
    private ModuleInfo buildModuleInfo(Directory libDir, String moduleName, Boolean resolve) {
        Boolean           isResolved  = False;
        Boolean           isWebModule = False;
        String[]          issues      = [];
        DependentModule[] dependents  = [];

        // get dependent modules
        @Inject("repository") ModuleRepository coreRepo;
        ModuleRepository accountRepo =
            new LinkedRepository([coreRepo, new DirRepository(libDir)].freeze(True));

        if (ModuleTemplate moduleTemplate := accountRepo.getModule(moduleName)) {
            for ((_, String dependentName) : moduleTemplate.moduleNamesByPath) {
                // everything depends on Ecstasy module; don't show it
                if (dependentName != TypeSystem.MackKernel) {
                    dependents +=
                        new DependentModule(dependentName, accountRepo.getModule(dependentName));
                }
            }
        }

        // resolve the module
        if (resolve) {
            try {
                TypeTemplate   webAppTemplate = WebApp.as(Type).template;
                ModuleTemplate moduleTemplate = accountRepo.getResolvedModule(moduleName);
                isResolved  = True;
                isWebModule = moduleTemplate.type.isA(webAppTemplate);
            } catch (Exception e) {
                issues += e.text?;
            }
        }

        return new ModuleInfo(moduleName, isResolved, isWebModule, issues, dependents);
    }
}