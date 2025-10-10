export function TitleAndSubTitle({ title, subtitle }) {
    return (
        <div className="text-center pb-4 mt-10 mb-8">
            <a
                href="https://github.com/leticarolina/defi-stablecoin"
                target="_blank"
                rel="noopener noreferrer"          >
                <h2 className="text-3xl md:text-4xl font-extrabold text-purple-800 hover:text-purple-600">
                    {title}
                </h2>
            </a>
            <p className="text-gray-600 mt-3 text-base md:text-lg mb-2 px-4">
                {subtitle}
            </p>
        </div>
    )
}