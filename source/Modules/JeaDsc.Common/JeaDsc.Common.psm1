using namespace System.Management.Automation.Language

function Convert-ObjectToHashtable
{
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Object
    )

    process
    {
        $hashtable = @{ }

        foreach ($property in $Object.PSObject.Properties.Where({ $_.Value }))
        {
            $hashtable.Add($property.Name, $property.Value)
        }

        $hashtable
    }
}

function ConvertTo-Expression
{
    <#
        .SYNOPSIS
            Serializes an object to a PowerShell expression.

        .DESCRIPTION
            The ConvertTo-Expression cmdlet converts (serializes) an object to a
            PowerShell expression. The object can be stored in a variable, file or
            any other common storage for later use or to be ported to another
            system.

            An expression can be restored to an object using the native
            Invoke-Expression cmdlet:

                $Object = Invoke-Expression ($Object | ConverTo-Expression)

            Or Converting it to a [scriptblock] and invoking it with cmdlets
            along with `Invoke-Command` or using the call operator (`&`):

                $Object = &([scriptblock]::Create($Object | ConverTo-Expression))

            An expression that is stored in a PowerShell (.ps1) file might also
            be directly invoked by the PowerShell dot-sourcing technique, e.g.:

                $Object | ConvertTo-Expression | Out-File .\Expression.ps1
                $Object = . .\Expression.ps1

            Warning: Invoking partly trusted input with Invoke-Expression or
            [scriptblock]::Create() methods could be abused by malicious code
            injections.

        .INPUTS
            Any. Each objects provided through the pipeline will converted to an
            expression. To concatinate all piped objects in a single expression,
            use the unary comma operator, e.g.: ,$Object | ConvertTo-Expression

        .OUTPUTS
            String[]. ConvertTo-Expression returns a PowerShell expression for
            each input object.

        .PARAMETER InputObject
            Specifies the objects to convert to a PowerShell expression. Enter a
            variable that contains the objects, or type a command or expression
            that gets the objects. You can also pipe one or more objects to
            ConvertTo-Expression.

        .PARAMETER Depth
            Specifies how many levels of contained objects are included in the
            PowerShell representation. The default value is 9.

        .PARAMETER Expand
            Specifies till what level the contained objects are expanded over
            separate lines and indented according to the -Indentation and
            -IndentChar parameters. The default value is equal to the -Depth value.

            A negative value will remove redundant spaces and compress the
            PowerShell expression to a single line (except for multi-line strings).

            Xml documents and multi-line strings are embedded in a "here string"
            and aligned to the left.

        .PARAMETER Indentation
            Specifies how many IndentChars to write for each level in the
            hierarchy.

        .PARAMETER IndentChar
            Specifies which character to use for indenting.

        .PARAMETER Strong
            By default, the ConvertTo-Expression cmdlet will return a weakly typed
            expression which is best for transfing objects between differend
            PowerShell systems.
            The -Strong parameter will strickly define value types and objects
            in a way that they can still be read by same PowerShell system and
            PowerShell system with the same configuration (installed modules etc.).

        .PARAMETER Explore
            In explore mode, all type prefixes are omitted in the output expression
            (objects will cast to to hash tables). In case the -Strong parameter is
            also supplied, all orginal (.Net) type names are shown.
            The -Explore switch is usefull for exploring object hyrachies and data
            type, not for saving and transfering objects.

        .EXAMPLE

            PS C:\> (Get-UICulture).Calendar | ConvertTo-Expression

            [pscustomobject]@{
                'AlgorithmType' = 1
                'CalendarType' = 1
                'Eras' = ,1
                'IsReadOnly' = $false
                'MaxSupportedDateTime' = [datetime]'9999-12-31T23:59:59.9999999'
                'MinSupportedDateTime' = [datetime]'0001-01-01T00:00:00.0000000'
                'TwoDigitYearMax' = 2029
            }

            PS C:\> (Get-UICulture).Calendar | ConvertTo-Expression -Strong

            [pscustomobject]@{
                'AlgorithmType' = [System.Globalization.CalendarAlgorithmType]'SolarCalendar'
                'CalendarType' = [System.Globalization.GregorianCalendarTypes]'Localized'
                'Eras' = [array][int]1
                'IsReadOnly' = [bool]$false
                'MaxSupportedDateTime' = [datetime]'9999-12-31T23:59:59.9999999'
                'MinSupportedDateTime' = [datetime]'0001-01-01T00:00:00.0000000'
                'TwoDigitYearMax' = [int]2029
            }

        .EXAMPLE

            PS C:\>Get-Date | Select-Object -Property * | ConvertTo-Expression | Out-File .\Now.ps1

            PS C:\>$Now = .\Now.ps1 # $Now = Get-Content .\Now.Ps1 -Raw | Invoke-Expression

            PS C:\>$Now

            Date        : 1963-10-07 12:00:00 AM
            DateTime    : Monday, October 7, 1963 10:47:00 PM
            Day         : 7
            DayOfWeek   : Monday
            DayOfYear   : 280
            DisplayHint : DateTime
            Hour        : 22
            Kind        : Local
            Millisecond : 0
            Minute      : 22
            Month       : 1
            Second      : 0
            Ticks       : 619388596200000000
            TimeOfDay   : 22:47:00
            Year        : 1963

        .EXAMPLE

            PS C:\>@{Account="User01";Domain="Domain01";Admin="True"} | ConvertTo-Expression -Expand -1 # Compress the PowerShell output

            @{'Admin'='True';'Account'='User01';'Domain'='Domain01'}

        .EXAMPLE

            PS C:\>WinInitProcess = Get-Process WinInit | ConvertTo-Expression # Convert the WinInit Process to a PowerShell expression

        .EXAMPLE

            PS C:\>Get-Host | ConvertTo-Expression -Depth 4 # Reveal complex object hierarchies

        .LINK
            https://www.powershellgallery.com/packages/ConvertFrom-Expression
    #>
    [CmdletBinding()]
    [OutputType([scriptblock])]
    param (
        [Parameter(ValueFromPipeLine = $true)]
        [Alias('InputObject')]
        [object]$Object,

        [Parameter()]
        [int]$Depth = 9,

        [Parameter()]
        [int]$Expand = $Depth,

        [Parameter()]
        [int]$Indentation = 1,

        [Parameter()]
        [string]$IndentChar = "`t",

        [Parameter()]
        [switch]$Strong,

        [Parameter()]
        [switch]$Explore,

        [Parameter()]
        [string]$NewLine = [System.Environment]::NewLine
    )
    begin
    {
        $listItem = $null
        $Tab = $IndentChar * $Indentation
        function Serialize
        {
            param (
                [Parameter()]
                [object]$Object,

                [Parameter()]
                $Iteration,

                [Parameter()]
                $Indent
            )

            function Quote
            {
                param (
                    [Parameter()]
                    [string]$Item
                )

                "'$($Item.Replace('''', ''''''))'"
            }
            function Here
            {
                param (
                    [Parameter()]
                    [string]$Item
                )

                if ($Item -match '[\r\n]')
                {
                    "@'$NewLine$Item$NewLine'@$NewLine"
                }
                else
                {
                    Quote -Item $Item
                }
            }
            function Stringify
            {
                param (
                    [Parameter()]
                    [object]$Object,

                    [Parameter()]
                    [string]$Cast = $Type,

                    [Parameter()]
                    [string]$Convert
                )

                $casted = $PSBoundParameters.ContainsKey('Cast')
                function Prefix
                {
                    param (
                        [Parameter()]
                        [object]$Object,

                        [Parameter()]
                        [switch]$Parenthesis
                    )

                    if ($Convert)
                    {
                        if ($listItem)
                        {
                            $Object = "($Convert $Object)"
                        }
                        else
                        {
                            $Object = "$Convert $Object"
                        }
                    }
                    if ($Parenthesis)
                    {
                        $Object = "($Object)"
                    }
                    if ($Explore)
                    {
                        if ($Strong)
                        {
                            "[$Type]$Object"
                        }
                        else
                        {
                            $Object
                        }
                    }
                    elseif ($Strong -or $casted)
                    {
                        if ($Cast)
                        {
                            "[$Cast]$Object"
                        }
                    }
                    else
                    {
                        $Object
                    }
                }
                function Iterate
                {
                    param (
                        [Parameter()]
                        [object]$Object,

                        [Parameter()]
                        [switch]$Strong = $Strong,

                        [Parameter()]
                        [switch]$listItem,

                        [Parameter()]
                        [switch]$Level
                    )

                    if ($Iteration -lt $Depth)
                    {
                        Serialize -Object $Object -Iteration ($Iteration + 1) -Indent ($Indent + 1 - [int][Bool]$Level)
                    }
                    else
                    {
                        "'...'"
                    }
                }
                if ($Object -is [string])
                {
                    Prefix -Object $Object
                }
                else
                {
                    $List = $null
                    $Properties = $null
                    $Methods = $Object.PSObject.Methods.Name

                    if ($Methods -contains 'GetEnumerator')
                    {
                        if ($Methods -contains 'get_Keys' -and $Methods -contains 'get_Values')
                        {
                            $List = [Ordered]@{ }
                            foreach ($Key in $Object.get_Keys())
                            {
                                $List[(Quote $Key)] = Iterate $Object[$Key]
                            }
                        }
                        else
                        {
                            $Level = @($Object).Count -eq 1 -or ($null -eq $Indent -and -not $Explore -and -not $Strong)
                            $StrongItem = $Strong -and $Type.Name -eq 'Object[]'
                            $List = @(foreach ($Item in $Object)
                                {
                                    Iterate $Item -ListItem -Level:$Level -Strong:$StrongItem
                                })
                        }
                    }
                    else
                    {
                        $Properties = $Object.PSObject.Properties | Where-Object { $_.MemberType -eq 'Property' }
                        if (-not $Properties)
                        {
                            $Properties = $Object.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' }
                        }
                        if ($Properties)
                        {
                            $List = [Ordered]@{ }; foreach ($Property in $Properties)
                            {
                                $List[(Quote $Property.Name)] = Iterate $Property.Value
                            }
                        }
                    }
                    if ($List -is [Array])
                    {
                        if (-not $casted -and ($Type.Name -eq 'Object[]' -or "$Type".Contains('.')))
                        {
                            $Cast = 'array'
                        }
                        if (-not $List.Count)
                        {
                            Prefix '@()'
                        }
                        elseif ($List.Count -eq 1)
                        {
                            if ($Strong)
                            {
                                Prefix "$List"
                            }
                            elseif ($listItem)
                            {
                                "(,$List)"
                            }
                            else
                            {
                                ",$List"
                            }
                        }
                        elseif ($Indent -ge $Expand - 1 -or $Type.GetElementType().IsPrimitive)
                        {
                            $Content = if ($Expand -ge 0)
                            {
                                $List -join ', '
                            }
                            else
                            {
                                $List -join ','
                            }
                            Prefix -Parenthesis:($listItem -or $Strong) $Content
                        }
                        elseif ($null -eq $Indent -and -not $Strong -and -not $Convert)
                        {
                            Prefix ($List -join ",$NewLine")
                        }
                        else
                        {
                            $LineFeed = $NewLine + ($Tab * $Indent)
                            $Content = "$LineFeed$Tab" + ($List -join ",$LineFeed$Tab")
                            if ($Convert)
                            {
                                $Content = "($Content)"
                            }
                            if ($listItem -or $Strong)
                            {
                                Prefix -Parenthesis "$Content$LineFeed"
                            }
                            else
                            {
                                Prefix $Content
                            }
                        }
                    }
                    elseif ($List -is [System.Collections.Specialized.OrderedDictionary])
                    {
                        if (-not $casted)
                        {
                            if ($Properties)
                            {
                                $casted = $true; $Cast = 'pscustomobject'
                            }
                            else
                            {
                                $Cast = 'hashtable'
                            }
                        }
                        if (-not $List.Count)
                        {
                            Prefix '@{}'
                        }
                        elseif ($Expand -lt 0)
                        {
                            Prefix ('@{' + (@(foreach ($Key in $List.get_Keys())
                                        {
                                            "$Key=" + $List[$Key]
                                        }) -join ';') + '}')
                        }
                        elseif ($List.Count -eq 1 -or $Indent -ge $Expand - 1)
                        {
                            Prefix ('@{' + (@(foreach ($Key in $List.get_Keys())
                                        {
                                            "$Key = " + $List[$Key]
                                        }) -join '; ') + '}')
                        }
                        else
                        {
                            $LineFeed = $NewLine + ($Tab * $Indent)
                            Prefix ("@{$LineFeed$Tab" + (@(foreach ($Key in $List.get_Keys())
                                        {
                                            if (($List[$Key])[0] -NotMatch '[\S]')
                                            {
                                                "$Key =" + $List[$Key].TrimEnd()
                                            }
                                            else
                                            {
                                                "$Key = " + $List[$Key].TrimEnd()
                                            }
                                        }) -join "$LineFeed$Tab") + "$LineFeed}")
                        }
                    }
                    else
                    {
                        Prefix ",$List"
                    }
                }
            }
            if ($null -eq $Object)
            {
                "`$null"
            }
            else
            {
                $Type = $Object.GetType()
                if ($Object -is [Boolean])
                {
                    if ($Object)
                    {
                        Stringify '$true'
                    }
                    else
                    {
                        Stringify '$false'
                    }
                }
                elseif ($Object -is [adsi])
                {
                    Stringify "'$($Object.ADsPath)'" $Type
                }
                elseif ('Char', 'mailaddress', 'Regex', 'Semver', 'Type', 'Version', 'Uri' -contains $Type.Name)
                {
                    Stringify "'$($Object)'" $Type
                }
                elseif ($Type.IsPrimitive)
                {
                    Stringify "$Object"
                }
                elseif ($Object -is [string])
                {
                    Stringify (Here $Object)
                }
                elseif ($Object -is [SecureString])
                {
                    Stringify "'$($Object | ConvertFrom-SecureString)'" -Convert 'ConvertTo-SecureString'
                }
                elseif ($Object -is [PSCredential])
                {
                    Stringify $Object.Username, $Object.Password -Convert 'New-Object PSCredential'
                }
                elseif ($Object -is [datetime])
                {
                    Stringify "'$($Object.ToString('o'))'" $Type
                }
                elseif ($Object -is [System.Enum])
                {
                    if ("$Type".Contains('.'))
                    {
                        Stringify "$(0 + $Object)"
                    }
                    else
                    {
                        Stringify "'$Object'" $Type
                    }
                }
                elseif ($Object -is [scriptblock])
                {
                    if ($Object -Match "\#.*?$")
                    {
                        Stringify "{$Object$NewLine}"
                    }
                    else
                    {
                        Stringify "{$Object}"
                    }
                }
                elseif ($Object -is [System.RuntimeTypeHandle])
                {
                    Stringify "$($Object.Value)"
                }
                elseif ($Object -is [xml])
                {
                    $sw = New-Object System.IO.StringWriter; $xw = New-Object System.Xml.XmlTextWriter $sw
                    $xw.Formatting = if ($Indent -lt $Expand - 1)
                    {
                        'Indented'
                    }
                    else
                    {
                        'None'
                    }
                    $xw.Indentation = $Indentation; $xw.IndentChar = $IndentChar; $Object.WriteContentTo($xw); Stringify (Here $sw) $Type
                }
                elseif ($Object -is [System.Data.DataTable])
                {
                    Stringify $Object.Rows
                }
                elseif ($Type.Name -eq "OrderedDictionary")
                {
                    Stringify $Object 'ordered'
                }
                elseif ($Object -is [System.ValueType])
                {
                    Stringify "'$($Object)'" $Type
                }
                else
                {
                    Stringify $Object
                }
            }
        }
    }
    process
    {
        (Serialize $Object).TrimEnd()
    }
}

function Convert-StringToObject
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [string[]]$InputString
    )

    process
    {
        foreach ($string in $InputString)
        {
            $parseErrors = @()
            $fakeCommand = "Totally-NotACmdlet -Fakeparameter $string"
            $ast = [Parser]::ParseInput($fakeCommand, [ref]$null, [ref]$parseErrors)
            if (-not $parseErrors)
            {
                # Use Ast.Find() to locate the CommandAst parsed from our fake command
                $cmdAst = $ast.Find( {
                        param (
                            [Parameter(Mandatory = $true)]
                            [System.Management.Automation.Language.Ast]$ChildAst
                        )
                        $ChildAst -is [CommandAst]
                    }
                    , $false
                )
                # Grab the user-supplied arguments (index 0 is the command name, 1 is our fake parameter)
                $allArgumentAst = $cmdAst.CommandElements.Where( { $_ -isnot [CommandparameterAst] -and $_.Value -ne 'Totally-NotACmdlet' })
                foreach ($argumentAst in $allArgumentAst)
                {
                    if ($argumentAst -is [ArrayLiteralAst])
                    {
                        # Argument was a list
                        foreach ($element in $argumentAst.Elements)
                        {
                            if ($element.StaticType.Name -eq 'String')
                            {
                                $element.value
                            }
                            if ($element.StaticType.Name -eq 'Hashtable')
                            {
                                [hashtable]$element.SafeGetValue()
                            }
                        }
                    }
                    else
                    {
                        if ($argumentAst -is [HashtableAst])
                        {
                            $ht = [Hashtable]$argumentAst.SafeGetValue()
                            for ($i = 0; $i -lt $ht.Keys.Count; $i++)
                            {
                                $value = $ht[([array]$ht.Keys)[$i]]
                                if ($value -is [scriptblock])
                                {
                                    $scriptBlockText = $value.Ast.Extent.Text

                                    if ($scriptBlockText[$value.Ast.Extent.StartOffset] -eq '{' -and $scriptBlockText[$value.Ast.Extent.EndOffset - 1] -eq '}')
                                    {
                                        $scriptBlockText = $scriptBlockText.Substring(0, $scriptBlockText.Length - 1)
                                        $scriptBlockText = $scriptBlockText.Substring(1, $scriptBlockText.Length - 1)
                                    }

                                    $ht[([array]$ht.Keys)[$i]] = [scriptblock]::Create($scriptBlockText)
                                }
                            }
                            $ht
                        }
                        elseif ($argumentAst -is [StringConstantExpressionAst])
                        {
                            $argumentAst.Value
                        }
                        else
                        {
                            Write-Error -Message "Input was not a valid hashtable, string or collection of both. Please check the contents and try again."
                        }
                    }
                }
            }
        }
    }
}

function Test-DscParameterState
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $CurrentValues,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $DesiredValues,

        [Parameter()]
        [System.String[]]
        $Properties,

        [Parameter()]
        [System.String[]]
        $ExcludeProperties,

        [Parameter()]
        [switch]
        $TurnOffTypeChecking,

        [Parameter()]
        [switch]
        $ReverseCheck,

        [Parameter()]
        [switch]
        $SortArrayValues
    )

    $returnValue = $true

    if ($CurrentValues -is [Microsoft.Management.Infrastructure.CimInstance] -or
        $CurrentValues -is [Microsoft.Management.Infrastructure.CimInstance[]])
    {
        $CurrentValues = Convert-ObjectToHashtable -Object $CurrentValues
    }

    if ($DesiredValues -is [Microsoft.Management.Infrastructure.CimInstance] -or
        $DesiredValues -is [Microsoft.Management.Infrastructure.CimInstance[]])
    {
        $DesiredValues = Convert-ObjectToHashtable -Object $DesiredValues
    }

    $types = 'System.Management.Automation.PSBoundParametersDictionary', 'System.Collections.Hashtable', 'Microsoft.Management.Infrastructure.CimInstance'

    if ($DesiredValues.GetType().FullName -notin $types)
    {
        New-InvalidArgumentException `
            -Message ($script:localizedData.InvalidDesiredValuesError -f $DesiredValues.GetType().FullName) `
            -ArgumentName 'DesiredValues'
    }

    if ($CurrentValues.GetType().FullName -notin $types)
    {
        New-InvalidArgumentException `
            -Message ($script:localizedData.InvalidCurrentValuesError -f $CurrentValues.GetType().FullName) `
            -ArgumentName 'CurrentValues'
    }

    if ($DesiredValues -is [Microsoft.Management.Infrastructure.CimInstance] -and -not $Properties)
    {
        New-InvalidArgumentException `
            -Message $script:localizedData.InvalidValuesToCheckError `
            -ArgumentName 'ValuesToCheck'
    }

    $desiredValuesClean = Remove-CommonParameter -Hashtable $DesiredValues

    if (-not $Properties)
    {
        $keyList = $desiredValuesClean.Keys
    }
    else
    {
        $keyList = $Properties
    }
    if ($ExcludeProperties)
    {
        $keyList = $keyList | Where-Object { $_ -notin $ExcludeProperties }
    }

    foreach ($key in $keyList)
    {
        $desiredValue = $desiredValuesClean.$key
        $currentValue = $CurrentValues.$key

        if ($desiredValue -is [Microsoft.Management.Infrastructure.CimInstance] -or
            $desiredValue -is [Microsoft.Management.Infrastructure.CimInstance[]])
        {
            $desiredValue = Convert-ObjectToHashtable -Object $desiredValue
        }
        if ($currentValue -is [Microsoft.Management.Infrastructure.CimInstance] -or
            $currentValue -is [Microsoft.Management.Infrastructure.CimInstance[]])
        {
            $currentValue = Convert-ObjectToHashtable -Object $currentValue
        }

        if ($desiredValue)
        {
            $desiredType = $desiredValue.GetType()
        }
        else
        {
            $desiredType = @{
                Name = 'Unknown'
            }
        }

        if ($currentValue)
        {
            $currentType = $currentValue.GetType()
        }
        else
        {
            $currentType = @{
                Name = 'Unknown'
            }
        }

        if ($currentType.Name -ne 'Unknown' -and $desiredType.Name -eq 'PSCredential')
        {
            # This is a credential object. Compare only the user name
            if ($currentType.Name -eq 'PSCredential' -and $currentValue.UserName -eq $desiredValue.UserName)
            {
                Write-Verbose -Message ($script:localizedData.MatchPsCredentialUsernameMessage -f $currentValue.UserName, $desiredValue.UserName)
                continue
            }
            else
            {
                Write-Verbose -Message ($script:localizedData.NoMatchPsCredentialUsernameMessage -f $currentValue.UserName, $desiredValue.UserName)
                $returnValue = $false
            }

            # Assume the string is our username when the matching desired value is actually a credential
            if ($currentType.Name -eq 'string' -and $currentValue -eq $desiredValue.UserName)
            {
                Write-Verbose -Message ($script:localizedData.MatchPsCredentialUsernameMessage -f $currentValue, $desiredValue.UserName)
                continue
            }
            else
            {
                Write-Verbose -Message ($script:localizedData.NoMatchPsCredentialUsernameMessage -f $currentValue, $desiredValue.UserName)
                $returnValue = $false
            }
        }

        if (-not $TurnOffTypeChecking)
        {
            if (($desiredType.Name -ne 'Unknown' -and $currentType.Name -ne 'Unknown') -and
                $desiredType.FullName -ne $currentType.FullName)
            {
                Write-Verbose -Message ($script:localizedData.NoMatchTypeMismatchMessage -f $key, $currentType.FullName, $desiredType.FullName)
                $returnValue = $false
                continue
            }
        }

        if ($currentValue -eq $desiredValue -and -not $desiredType.IsArray)
        {
            Write-Verbose -Message ($script:localizedData.MatchValueMessage -f $desiredType.FullName, $key, $currentValue, $desiredValue)
            continue
        }

        if ($desiredValuesClean.GetType().Name -in 'HashTable', 'PSBoundParametersDictionary')
        {
            $checkDesiredValue = $desiredValuesClean.ContainsKey($key)
        }
        else
        {
            $checkDesiredValue = Test-DscObjectHasProperty -Object $desiredValuesClean -PropertyName $key
        }

        if (-not $checkDesiredValue)
        {
            Write-Verbose -Message ($script:localizedData.MatchValueMessage -f $desiredType.FullName, $key, $currentValue, $desiredValue)
            continue
        }

        if ($desiredType.IsArray)
        {
            Write-Verbose -Message ($script:localizedData.TestDscParameterCompareMessage -f $key, $desiredType.FullName)

            if (-not $currentValue -and -not $desiredValue)
            {
                Write-Verbose -Message ($script:localizedData.MatchValueMessage -f $desiredType.FullName, $key, 'empty array', 'empty array')
                continue
            }
            elseif (-not $currentValue)
            {
                Write-Verbose -Message ($script:localizedData.NoMatchValueMessage -f $desiredType.FullName, $key, $currentValue, $desiredValue)
                $returnValue = $false
                continue
            }
            elseif ($currentValue.Count -ne $desiredValue.Count)
            {
                Write-Verbose -Message ($script:localizedData.NoMatchValueDifferentCountMessage -f $desiredType.FullName, $key, $currentValue.Count, $desiredValue.Count)
                $returnValue = $false
                continue
            }
            else
            {
                $desiredArrayValues = $desiredValue
                $currentArrayValues = $currentValue

                if ($SortArrayValues)
                {
                    $desiredArrayValues = @($desiredArrayValues | Sort-Object)
                    $currentArrayValues = @($currentArrayValues | Sort-Object)
                }

                for ($i = 0; $i -lt $desiredArrayValues.Count; $i++)
                {
                    if ($desiredArrayValues[$i])
                    {
                        $desiredType = $desiredArrayValues[$i].GetType()
                    }
                    else
                    {
                        $desiredType = @{
                            Name = 'Unknown'
                        }
                    }

                    if ($currentArrayValues[$i])
                    {
                        $currentType = $currentArrayValues[$i].GetType()
                    }
                    else
                    {
                        $currentType = @{
                            Name = 'Unknown'
                        }
                    }

                    if (-not $TurnOffTypeChecking)
                    {
                        if (($desiredType.Name -ne 'Unknown' -and $currentType.Name -ne 'Unknown') -and
                            $desiredType.FullName -ne $currentType.FullName)
                        {
                            Write-Verbose -Message ($script:localizedData.NoMatchElementTypeMismatchMessage -f $key, $i, $currentType.FullName, $desiredType.FullName)
                            $returnValue = $false
                            continue
                        }
                    }

                    #Convert a scriptblock into a string as scriptblocks are not comparable
                    $wasCurrentArrayValuesConverted = $false
                    if ($currentArrayValues[$i] -is [scriptblock])
                    {
                        $currentArrayValues[$i] = if ($desiredArrayValues[$i] -is [string])
                        {
                            $currentArrayValues[$i] = $currentArrayValues[$i].Invoke()
                        }
                        else
                        {
                            $currentArrayValues[$i].ToString()
                        }
                        $wasCurrentArrayValuesConverted = $true
                    }
                    if ($desiredArrayValues[$i] -is [scriptblock])
                    {
                        $desiredArrayValues[$i] = if ($currentArrayValues[$i] -is [string] -and -not $wasCurrentArrayValuesConverted)
                        {
                            $desiredArrayValues[$i].Invoke()
                        }
                        else
                        {
                            $desiredArrayValues[$i].ToString()
                        }
                    }

                    if ($desiredType -eq [System.Collections.Hashtable] -and $currentType -eq [System.Collections.Hashtable])
                    {
                        $param = $PSBoundParameters
                        $param.CurrentValues = $currentArrayValues[$i]
                        $param.DesiredValues = $desiredArrayValues[$i]
                        $null = $param.Remove('ValuesToCheck')

                        if ($returnValue)
                        {
                            $returnValue = Test-DscParameterState @param
                        }
                        else
                        {
                            Test-DscParameterState @param | Out-Null
                        }
                        continue
                    }

                    if ($desiredArrayValues[$i] -ne $currentArrayValues[$i])
                    {
                        Write-Verbose -Message ($script:localizedData.NoMatchElementValueMismatchMessage -f $i, $desiredType.FullName, $key, $currentArrayValues[$i], $desiredArrayValues[$i])
                        $returnValue = $false
                        continue
                    }
                    else
                    {
                        Write-Verbose -Message ($script:localizedData.MatchElementValueMessage -f $i, $desiredType.FullName, $key, $currentArrayValues[$i], $desiredArrayValues[$i])
                        continue
                    }
                }

            }
        }
        elseif ($desiredType -eq [System.Collections.Hashtable] -and $currentType -eq [System.Collections.Hashtable])
        {
            $param = $PSBoundParameters
            $param.CurrentValues = $currentValue
            $param.DesiredValues = $desiredValue
            $null = $param.Remove('ValuesToCheck')

            if ($returnValue)
            {
                $returnValue = Test-DscParameterState @param
            }
            else
            {
                Test-DscParameterState @param | Out-Null
            }
            continue
        }
        else
        {
            #Convert a scriptblock into a string as scriptblocks are not comparable
            $wasCurrentValue = $false
            if ($currentValue -is [scriptblock])
            {
                $currentValue = if ($desiredValue -is [string])
                {
                    $currentValue = $currentValue.Invoke()
                }
                else
                {
                    $currentValue.ToString()
                }
                $wasCurrentValue = $true
            }
            if ($desiredValue -is [scriptblock])
            {
                $desiredValue = if ($currentValue -is [string] -and -not $wasCurrentValue)
                {
                    $desiredValue.Invoke()
                }
                else
                {
                    $desiredValue.ToString()
                }
            }

            if ($desiredValue -ne $currentValue)
            {
                Write-Verbose -Message ($script:localizedData.NoMatchValueMessage -f $desiredType.FullName, $key, $currentValue, $desiredValue)
                $returnValue = $false
            }
        }
    }

    if ($ReverseCheck)
    {
        Write-Verbose -Message $script:localizedData.StartingReverseCheck
        $reverseCheckParameters = $PSBoundParameters
        $reverseCheckParameters.CurrentValues = $DesiredValues
        $reverseCheckParameters.DesiredValues = $CurrentValues
        $null = $reverseCheckParameters.Remove('ReverseCheck')

        if ($returnValue)
        {
            $returnValue = Test-DscParameterState @reverseCheckParameters
        }
        else
        {
            $null = Test-DscParameterState @reverseCheckParameters
        }
    }

    Write-Verbose -Message ($script:localizedData.TestDscParameterResultMessage -f $returnValue)
    return $returnValue
}

function New-InvalidArgumentException
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Message,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ArgumentName
    )

    $argumentException = New-Object -TypeName 'ArgumentException' `
        -ArgumentList @($Message, $ArgumentName)

    $newObjectParameters = @{
        TypeName     = 'System.Management.Automation.ErrorRecord'
        ArgumentList = @($argumentException, $ArgumentName, 'InvalidArgument', $null)
    }

    $errorRecord = New-Object @newObjectParameters

    throw $errorRecord
}

function Remove-CommonParameter
{
    [OutputType([System.Collections.Hashtable])]
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Hashtable
    )

    $inputClone = $Hashtable.Clone()
    $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters
    $commonParameters += [System.Management.Automation.PSCmdlet]::OptionalCommonParameters

    $Hashtable.Keys | Where-Object -FilterScript {
        $_ -in $commonParameters
    } | foreach-Object -Process {
        $inputClone.Remove($_)
    }

return $inputClone
}

function Get-LocalizedData
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ResourceName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ScriptRoot
    )

    if (-not $ScriptRoot)
    {
        $dscResourcesFolder = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'DSCResources'
        $resourceDirectory = Join-Path -Path $dscResourcesFolder -ChildPath $ResourceName
    }
    else
    {
        $resourceDirectory = $ScriptRoot
    }

    $localizedStringFileLocation = Join-Path -Path $resourceDirectory -ChildPath $PSUICulture

    if (-not (Test-Path -Path $localizedStringFileLocation))
    {
        # Fallback to en-US
        $localizedStringFileLocation = Join-Path -Path $resourceDirectory -ChildPath 'en-US'
    }

    Import-LocalizedData `
        -BindingVariable localizedData `
        -FileName "$ResourceName.strings.psd1" `
        -BaseDirectory $localizedStringFileLocation

    return $localizedData
}

function Sync-Parameter
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                $_ -is [System.Management.Automation.FunctionInfo] -or
                $_ -is [System.Management.Automation.CmdletInfo] -or
                $_ -is [System.Management.Automation.ExternalScriptInfo] -or
                $_ -is [System.Management.Automation.AliasInfo]
            })]
        [object]$Command,

        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    if ($Command -is [System.Management.Automation.AliasInfo] -and $Command.Definition -like 'PesterMock*')
    {
        $Command = Get-Command -Name $Command.Name
    }

    $commonParameters = [System.Management.Automation.Internal.CommonParameters].GetProperties().Name
    $commandParameterKeys = $Command.Parameters.Keys.GetEnumerator() | foreach-Object { $_ }
    $parameterKeys = $Parameters.Keys.GetEnumerator() | foreach-Object { $_ }

    $keysToRemove = Compare-Object -ReferenceObject $commandParameterKeys -DifferenceObject $parameterKeys |
        Select-Object -ExpandProperty InputObject

    $keysToRemove = $keysToRemove + $commonParameters | Select-Object -Unique #remove the common parameters

    foreach ($key in $keysToRemove)
    {
        $Parameters.Remove($key)
    }

    $Parameters
}

$script:localizedData = Get-LocalizedData `
    -ResourceName 'JeaDsc.Common' `
    -ScriptRoot $PSScriptRoot
