# Run Tekton Chains in its own cluster.
This repo has the scripts to run Tekton chains in its own cluster.
Currently this is not working.
Tekton chains does not come up.

### Methodology
The Knative injection can create a client which interacts with a cluster different from where this is launched.

To achieve this, there is a flagSet defined at [ ParseAndGetRESTConfigOrDie()](https://github.com/knative/pkg/blob/247510c00e9dbb7f5a23b76e8ab76654de173a04/injection/config.go#L30) which is on the call chain of the main function of the Chains controller.

This expects a 
- cluster (the cluster for which we need the client)
- kubeconfig (path to a file which has the kubconfig)

To provide these, the chains deployment yaml was modified 
- To provide these as arguments
- The kubeconfig is passed in as a configMap and mounted into /mnt/kubeconfig/config which is then passed as an argument to the controller.

### Issues identified
#### Fixed
* The configMap was initially created in the default namespace and Chains could not pick it up. Fixed by creating it in the tekton-chains namespace.
* Flags can only be parsed once after all the flags are defined. Tekton Chains parses flags upfront in [main](https://github.com/tektoncd/chains/blob/b4e5b533bef8c247f8d2714cab1cf5453a2b4e81/cmd/controller/main.go#L41) even before the other flags get defined. Fix was a hack to not call flag.Parse in main which meant that the namespace for informers had to be hardcoded to "", which for now is ok.
#### Unfixed
* The deployment now throws up an error "Error: flags cannot be placed before plugin name: --context=gke_jagathprakash-test_us-central1_chains". Debugging this.

