package model {
    typedef UInt as AccountId;
    typedef UInt as UserId;

    enum UserRole {Admin, Developer, Observer}

    const AccountInfo(AccountId id, String name,
                      Map<String, ModuleInfo> modules = [], // keyed by the fully qualified name
                      Map<String, WebAppInfo> webApps = [], // keyed by the deployment name
                      Map<UserId, UserRole>   users   = []
                      ) {

        AccountInfo addOrUpdateModule(ModuleInfo info) {
            return new AccountInfo(id, name, modules.put(info.name, info), webApps, users);
        }

        AccountInfo removeModule(String moduleName) {
            return new AccountInfo(id, name, modules.remove(moduleName), webApps, users);
        }

        AccountInfo addOrUpdateUser(UserId userId, UserRole role) {
            return new AccountInfo(id, name, modules, webApps, users.put(userId, role));
        }

        AccountInfo removeUser(UserId userId) {
            return new AccountInfo(id, name, modules, webApps, users.remove(userId));
        }

        AccountInfo addOrUpdateWebApp(WebAppInfo info) {
            return new AccountInfo(id, name, modules, webApps.put(info.deployment, info), users);
        }

        AccountInfo removeWebApp(String deployment) {
            return new AccountInfo(id, name, modules, webApps.remove(deployment), users);
        }

        /**
         * @return the name of deployments that depend on the specified module(s)
         */
        Set<String> collectDeployments(String moduleName) {
            Set<String> deployments = new HashSet();

            for ((String deployment, WebAppInfo webAppInfo) : webApps) {
                String webModuleName = webAppInfo.moduleName;
                if (webModuleName == moduleName) {
                    deployments += deployment;
                } else if (ModuleInfo moduleInfo := modules.get(webModuleName),
                    moduleInfo.dependsOn(moduleName)) {
                    deployments += deployment;
                }
            }

            return deployments;
        }
    }

    const AccountUser(UserId userId, AccountId accountId);

    const UserInfo(UserId id, String name, String email);

    enum ModuleType default(Generic) {Generic, Web, Db}
    const ModuleInfo(
        String           name,       // qualified
        Boolean          isResolved,
        ModuleType       moduleType,
        String[]         issues,
        RequiredModule[] dependencies
        ) {
            /**
             * @return True iff this module depends on the specified module
             */
            Boolean dependsOn(String moduleName) {
                return dependencies.any(rm -> rm.name == moduleName);
            }
        }

    const RequiredModule(
        String  name,      // qualified
        Boolean available);

    const WebAppInfo(
        String  deployment, // the same module could be deployed multiple times
        String  moduleName, // qualified
        String  hostName,
        String  bindAddr,
        UInt16  httpPort,
        UInt16  httpsPort,
        Boolean active) {

        assert() {
            // for now, the ports are consecutive and the http port is an even number
            assert httpPort % 2 == 0 && httpsPort == httpPort + 1;
        }

        WebAppInfo updateStatus(Boolean active) {
            return new WebAppInfo(deployment, moduleName,
                                  hostName, bindAddr, httpPort, httpsPort, active);
        }
    }
}