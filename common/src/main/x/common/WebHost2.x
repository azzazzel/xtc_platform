import ecstasy.mgmt.Container;

import common.model2.WebAppInfo;


/**
 * AppHost for a Web module.
 */
const WebHost2
        extends AppHost {

    construct (Container container, WebAppInfo info, Directory homeDir,
               function void() shutdown, AppHost[] dependents) {
        construct AppHost(info.moduleName, homeDir);

        this.container  = container;
        this.info       = info;
        this.shutdown   = shutdown;
        this.dependents = dependents;
    }

    /**
     * The web application details.
     */
    WebAppInfo info;

    /**
     * The function that would shutdown the HTTP server for this module.
     */
    function void() shutdown;

    /**
     * The AppHosts for the containers this module depends on.
     */
    AppHost[] dependents;


    // ----- Closeable -----------------------------------------------------------------------------

    @Override
    void close(Exception? e = Null) {
        for (AppHost dependent : dependents) {
            dependent.close(e);
        }
        shutdown();

        super(e);
    }
}