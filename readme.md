# Azure Confidential Computing: Secure Key Release

## Description

As I was researching confidential computing this year, I heard about “Secure Key Release” being mentioned in a couple of Azure Confidential Compute-related videos, such as this one from Ignite 2022.

> 💡 At the time of writing Microsoft offers a couple of mechanisms for customers to utilize confidential computing, all are based on the notion of running your applications in hardware-based trusted execution environments (TEE). Picking a particular approach boils down to how much of a trusted computing base (TCB), you are willing to take on. The more code we end up running inside of the TEE, the larger the TCB becomes and potentially your attack surface. If one component inside the TCB is compromised, the entire system’s security may be jeopardized. I have written about this subject at length a few months ago in a different blog post, feel free to take a look.

I had been wondering how one would go about using this feature, so in this blog post I set out to do just that. I will be taking a look at how to release an HSM key from Azure Key Vault to a Trusted Execution Environment, in our case an Azure Confidential Virtual Machine, powered by AMD SEV-SNP.

Azure Key Vault’s secure key release mechanism should let us get more control over which applications get access to a specific key.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FThomVanL%2F%2Fblog-2022-12-azure-confidential-computing-secure-key-release%2Fmain%2Fbicep%2Fmain.json)

## 🔗 Links

- [Full blog post](https://thomasvanlaere.com/posts/2022/02/exploring-windows-containers-page-files/)
