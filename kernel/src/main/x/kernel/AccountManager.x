import ecstasy.text.Log;

import ecstasy.mgmt.DirRepository;
import ecstasy.mgmt.LinkedRepository;

import common.DbHost;
import common.WebHost;

import common.model.AccountId;
import common.model.AccountInfo;
import common.model.ModuleInfo;
import common.model.UserId;
import common.model.UserInfo;
import common.model.WebAppInfo;

import common.utils;

import oodb.DBMap;
import oodb.DBUser;


/**
 * The module for basic hosting functionality.
 */
service AccountManager
        implements common.AccountManager {

    @Unassigned
    DbHost platformDbHost;

    @Unassigned
    platformDB.Connection dbConnection;

    /**
     * Initialize the service.
     *
     * @param repository  the core [ModuleRepository]
     * @param homeDir     the platform home directory (e.g. "~/xqiz.it/platform/host")
     * @param buildDir    the directory to place auto-generated modules at  (e.g. "~/xqiz.it/platform/build")
     * @param errors      the error log
     */
    void init(ModuleRepository repository, Directory homeDir, Directory buildDir, Log errors) {
        repository = new LinkedRepository([new DirRepository(buildDir), repository].freeze(True));
        assert platformDbHost := utils.createDbHost(repository, "platformDB.xqiz.it", "jsondb",
                                                    homeDir, buildDir, errors);

        DBUser user = new oodb.model.User(1, "admin");
        dbConnection = platformDbHost.ensureDatabase()(user).as(platformDB.Connection);

        // TEMPORARY: TODO remove after "add user" functionality is implemented
        DBMap<AccountId, AccountInfo> accounts = dbConnection.accounts;
        DBMap<UserId, UserInfo>       users    = dbConnection.users;
        if (!accounts.contains(1)) {
            UserInfo admin = new UserInfo(1, "admin", "admin@acme.com");
            users.put(1, admin);
            accounts.put(1, new AccountInfo(1, "acme", [], [], Map:[1 = Admin]));
        }

        if (!accounts.contains(2)) {
            UserInfo admin = new UserInfo(2, "admin", "admin@cvs.com");
            users.put(2, admin);
            accounts.put(2, new AccountInfo(2, "cvs", [], [], Map:[2 = Admin]));
        }
    }

    @Override
    conditional AccountInfo getAccount(String accountName) {
        return dbConnection.accounts.values.any(info -> info.name == accountName);
    }

    @Override
    void addOrUpdateModule(String accountName, ModuleInfo moduleInfo) {
        using (val tx = dbConnection.createTransaction()) {
            if (AccountInfo accountInfo := getAccount(accountName)) {
                tx.accounts.put(accountInfo.id, accountInfo.addOrUpdateModule(moduleInfo));
            }
        }
    }

    @Override
    void removeModule(String accountName, String moduleName) {
        using (val tx = dbConnection.createTransaction()) {
            if (AccountInfo accountInfo := getAccount(accountName)) {
                tx.accounts.put(accountInfo.id, accountInfo.removeModule(moduleName));
            }
        }
    }

    @Override
    void addOrUpdateWebApp(String accountName, WebAppInfo webAppInfo) {
        using (val tx = dbConnection.createTransaction()) {
            if (AccountInfo accountInfo := getAccount(accountName)) {
                if (!accountInfo.webApps.contains(webAppInfo.deployment)) {
                    // update the "allocatedPorts" table
                    tx.allocatedPorts.put(webAppInfo.httpPort, accountInfo.id);
                }
                tx.accounts.put(accountInfo.id, accountInfo.addOrUpdateWebApp(webAppInfo));
            }
        }
    }

    @Override
    void removeWebApp(String accountName, String appName) {
        using (val tx = dbConnection.createTransaction()) {
            if (AccountInfo accountInfo := getAccount(accountName),
                WebAppInfo  webAppInfo  := accountInfo.webApps.get(appName)) {

                tx.accounts.put(accountInfo.id, accountInfo.removeWebApp(appName));
                // update the "allocatedPorts" table
                dbConnection.allocatedPorts.remove(webAppInfo.httpPort);
            }
        }
    }


    @Override
    conditional UInt16 allocatePort(Range<UInt16> range) {
        using (val tx = dbConnection.createTransaction()) {
            DBMap<UInt16, AccountId> allocatedPorts = dbConnection.allocatedPorts;

            for (UInt16 port = range.lowerBound; port < range.upperBound; port += 2) {
                if (!allocatedPorts.contains(port)) {
                    return True, port;
                }
            }
            return False;
        }
    }

    @Override
    void shutdown() {
        platformDbHost.closeDatabase();
    }
}